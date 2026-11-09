"""Bit-exact golden model of QC18-ACC: executes the descriptor program ONLY from the memory images
(descriptor RAM, weight SRAM, param SRAM, activation buffers).  Vectorised per pass over all tiles and a batch
of images; the arithmetic is exactly the hardware's (20-b PE accumulators, PPU int32/int64 requant, head).

Activation buffers: uint64 [N, 3, 8192], flat position = bank * 1024 + address (layout.flat).
PE math: y[i] = t1 x[(i + k1) mod 8] + t2 x[(i + k2) mod 8] per block, accumulated over K blocks.  Default path:
the decoded codes are expanded to their 8x8 blocks and the K-sum runs as one fp32 GEMM (exact: every partial sum
is an integer < 2^19 < 2^24, proved by the compiler and asserted here).  literal=True evaluates the per-block
two-term formula directly (gathers, no GEMM) as a cross-check, with the activations taken through the v2 kw window
(gather_window: raw 8-word window, shifted by one lane on a consecutive tap, only the read slots loaded from the
buffer, padding mask at the array input), i.e. the RTL's data path, instead of the direct per-tap gather.
"""
import numpy as np

from . import codes as K
from .layout import DEPTH, flat, gather_plan, join16, read_tensor, split16, window_plan, words_to_lanes, write_tensor
from .program import RAW16, RELU, RES_ID, RES_R, read_program

ACC_LIM = 2 ** 19


def rq(v, m0, sh):
    """(v m0 + 2^(sh-1)) >>> sh, int64 (== qc18.int8.requant)."""
    return (v * m0 + (np.int64(1) << (sh - 1))) >> sh


class Golden:
    def __init__(self, images):
        self.w, self.p = images["weights"], images["params"]
        self.prog = read_program(images["desc"])
        self.convs, self.head = self.prog[:-1], self.prog[-1]
        self.cache = {}

    def _pass_data(self, i, d):
        if i not in self.cache:
            n = d.cout64 * d.k * d.k * d.cin8
            cds = K.word_codes(self.w[d.wbase:d.wbase + n])                       # [og*K + kb, g]
            Kb = d.k * d.k * d.cin8
            cds = cds.reshape(d.cout64, Kb, 8).transpose(0, 2, 1).reshape(d.cout64 * 8, Kb)   # [r, kb]
            kk, tt = K.decode(cds)                                                 # [r, kb, 2]
            blk = np.zeros((cds.shape[0], Kb, 8, 8), np.float32)                   # [r, kb, i, j]
            ii = np.arange(8)
            for j in range(2):
                np.add.at(blk, (np.arange(cds.shape[0])[:, None, None], np.arange(Kb)[None, :, None], ii,
                                (ii + kk[:, :, j, None]) % 8), tt[:, :, j, None].astype(np.float32))
            Wd = np.ascontiguousarray(blk.transpose(1, 3, 0, 2).reshape(Kb * 8, -1))  # [(kb, j), (r, i)]
            prm = K.param_fields(self.p[d.pbase:d.pbase + 64 * d.cout64])
            self.cache[i] = (gather_plan(d), Wd, kk, tt, prm)
        return self.cache[i]

    def conv(self, act, i, d, literal=False):
        (pos, val), Wd, kk, tt, (bias, m0, sh, dd) = self._pass_data(i, d)
        N, P, Kb, Co = act.shape[0], d.Hout * d.Wout, pos.shape[1], 64 * d.cout64
        if literal:
            x = gather_window(act[:, d.in_buf], d)
            acc = pe_literal(x, kk, tt).reshape(N, P, Co)
        else:
            x = words_to_lanes(act[:, d.in_buf][:, pos]) * val[None, :, :, None]   # AGU + padding [N,P,Kb,8]
            acc = (x.reshape(N * P, Kb * 8).astype(np.float32) @ Wd).astype(np.int64).reshape(N, P, Co)
        assert np.abs(acc).max() < ACC_LIM, "20-b accumulator overflow"
        v = np.where(dd == 1, -acc, acc) + bias
        assert np.abs(v).max() < 2 ** 31, "int32 overflow"
        y = rq(v, m0, sh)
        y = np.moveaxis(y.reshape(N, d.Hout, d.Wout, Co), 3, 1)                    # [N, C, H, W]
        if d.mode == RAW16:
            assert np.abs(y).max() < 2 ** 15, "RAW16 overflow"
            write_tensor(act[:, d.out_buf], split16(y), d.out_lay, d.out_base)
            return
        if d.mode == RES_ID:
            q = read_tensor(act[:, d.res_buf], d.res_lay, d.res_base, Co, d.Hout, d.Wout).astype(np.int64)
            y = y + rq(q, np.int64(d.idm0), np.int64(d.idsh))
        elif d.mode == RES_R:
            y = y + join16(read_tensor(act[:, d.res_buf], d.res_lay, d.res_base, 2 * Co, d.Hout, d.Wout))
        else:
            assert d.mode == RELU
        write_tensor(act[:, d.out_buf], np.clip(y, 0, 127), d.out_lay, d.out_base)

    def run_head(self, act):
        h = self.head
        f = read_tensor(act[:, h.in_buf], h.in_lay, h.in_base, 8 * h.cin8, h.Hin, h.Win).astype(np.int64)
        p = np.clip(rq(f.sum((2, 3)), np.int64(h.pool_m0), np.int64(h.pool_sh)), 0, 127)   # [N, 512]
        W = K.fc_weights(self.w[h.wbase:h.wbase + h.cin8 * h.ncls]).reshape(h.cin8, h.ncls, 8)
        W = W.transpose(1, 0, 2).reshape(h.ncls, 8 * h.cin8)                     # W8[j, 8 cb + lane]
        bias = K.param_fields(self.p[h.pbase:h.pbase + h.ncls])[0]
        acc = p @ W.T + bias
        assert np.abs(acc).max() < 2 ** 31
        return acc, p

    def run(self, act, snap=True, literal=False):
        """act uint64 [N, 3, 8192] (initial buffers; modified in place) -> (logits int64 [N, 10],
        [out-buffer snapshot after each pass], pooled features)."""
        snaps = []
        for i, d in enumerate(self.convs):
            self.conv(act, i, d, literal)
            if snap:
                snaps.append(act[:, d.out_buf].copy())
        logits, p = self.run_head(act)
        return logits, snaps, p


def gather_window(buf, d):
    """Array inputs [N, P, Kb, 8] of a pass through the kw window (layout.window_plan): per tile and step the
    window W[8] (raw words, slot j = index B + j) is shifted by one slot on a shift step, the read slots are loaded
    from the buffer (flat position of index B + j; never-read slots stay 0 here, X in hardware), and row p gets
    W[p] if lane p is valid, else 0."""
    w = window_plan(d)
    N, T, S = buf.shape[0], w["base"].shape[0], w["base"].shape[1]
    W = np.zeros((N, T, 8), np.uint64)
    out = np.zeros((N, T, S, 8, 8), np.int8)
    j = np.arange(8)
    for s in range(S):
        if w["shift"][s]:
            W = np.concatenate([W[:, :, 1:], np.zeros((N, T, 1), np.uint64)], 2)
        else:
            W = np.zeros_like(W)
        idx = w["base"][:, s, None] + j                                            # [T, 8]
        rd = w["read"][:, s]
        assert (idx[rd] >= 0).all() and (d.in_base + (idx[rd] >> 3) < DEPTH).all(), "window read outside the buffer"
        pos = flat(np.where(rd, idx, 0), d.in_base)
        W = np.where(rd[None], buf[:, pos], W)
        out[:, :, s] = words_to_lanes(W) * w["lane"][None, :, s, :, None]
    return out.transpose(0, 1, 3, 2, 4).reshape(N, T * 8, S, 8)


def pe_literal(x, kk, tt, chunk=8):
    """Block-PE formula: acc[n, p, r, i] = sum_kb t1 x[n, p, kb, (i+k1) % 8] + t2 x[n, p, kb, (i+k2) % 8]."""
    N, P, Kb, _ = x.shape
    R = kk.shape[0]
    ii, kb = np.arange(8), np.arange(Kb)[None, :, None]
    acc = np.zeros((N, P, R, 8), np.int64)
    for r0 in range(0, R, chunk):
        for j in range(2):
            lane = (ii + kk[r0:r0 + chunk, :, j, None]) % 8                        # [r, Kb, 8]
            g = x[:, :, kb, lane].astype(np.int64)                                 # [N, P, r, Kb, 8]
            acc[:, :, r0:r0 + chunk] += (g * tt[r0:r0 + chunk, :, j, None]).sum(3)
    return acc


# ---- cycle model (MODEL, not measured) -----------------------------------------------------------------------
def cycles(images):
    """Per pass: tiles x max(K, drain) + 64-cycle param load per og; drain = 64 (128 for RAW16 / RES_R:
    2 bank accesses per output word).  Head estimate: 16 pixel reads + 10 FC words per cb, + 16."""
    prog = read_program(images["desc"])
    out = []
    for d in prog[:-1]:
        tiles = d.Hout * d.Wout // 8 * d.cout64
        drain = 128 if d.mode in (RAW16, RES_R) else 64
        out.append(tiles * max(d.k * d.k * d.cin8, drain) + 64 * d.cout64)
    h = prog[-1]
    out.append(h.cin8 * (h.Hin * h.Win + h.ncls) + 16)
    return out


def act_reads(images):
    """Array act-bank reads per conv pass (MODEL of the RTL counter CSR_ACT_RD): [(v2 window, v1 per lane)]."""
    from .layout import act_reads as ar
    return [ar(d) for d in read_program(images["desc"])[:-1]]
