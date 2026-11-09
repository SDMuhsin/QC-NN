"""Bit-exact golden model of QC18-ACC v3 (Kb = 2): executes the descriptor program ONLY from the v3 memory images
(descriptor RAM, even / odd weight SRAM, param SRAM, 128-b activation buffers).  Same arithmetic as v2 (20-b PE
accumulators, PPU requant, head) plus the v3 20-b PPU v register (asserted |d acc + bias| < 2^19).

Activation buffers: uint64 [N, 3, 4096, 2] (flat position bank * 512 + address; lo, hi half).
PE step: y += B_e x_e + B_o x_o (two blocks of one pair step).  Default path: the codes expanded to 8x8 blocks, one
fp32 GEMM over all steps (exact: integers < 2^19 < 2^24).  literal=True: the per-block two-term formula on the inputs
gathered through the v3 kw window (gather_window: 128-b raw words), i.e. the RTL's data path.
"""
import numpy as np

from qc18acc.compile import codes as K
from qc18acc.compile.golden import pe_literal, rq
from qc18acc.compile.program import RAW16, RELU, RES_ID, RES_R, read_program

from .layout import DEPTH, cinp, flat, gather_plan, join16, read_tensor, split16, window_plan, words_to_lanes, write_tensor

ACC_LIM, V_LIM = 2 ** 19, 2 ** 19


def lanes16(words):
    """uint64 [..., 2] -> int8 [..., 16] (lanes 0..7 = lo half, 8..15 = hi half)."""
    return words_to_lanes(np.ascontiguousarray(words)).reshape(words.shape[:-1] + (16,))


class Golden3:
    def __init__(self, images):
        self.we, self.wo, self.p = images["weights_e"], images["weights_o"], images["params"]
        self.prog = read_program(images["desc"])
        self.convs, self.head = self.prog[:-1], self.prog[-1]
        self.cache = {}

    def _pass_data(self, i, d):
        if i not in self.cache:
            S = d.k * d.k * cinp(d.cin8)
            n = d.cout64 * S
            cds = np.stack([K.word_codes(w[d.wbase:d.wbase + n]) for w in (self.we, self.wo)], -1)  # [og*S+s, g, h]
            cds = cds.reshape(d.cout64, S, 8, 2).transpose(0, 2, 1, 3).reshape(d.cout64 * 8, 2 * S)  # [r, (s, h)]
            kk, tt = K.decode(cds)                                                 # [r, 2S, 2]
            R = cds.shape[0]
            blk = np.zeros((R, 2 * S, 8, 8), np.float32)
            ii = np.arange(8)
            for j in range(2):
                np.add.at(blk, (np.arange(R)[:, None, None], np.arange(2 * S)[None, :, None], ii,
                                (ii + kk[:, :, j, None]) % 8), tt[:, :, j, None].astype(np.float32))
            Wd = np.ascontiguousarray(blk.transpose(1, 3, 0, 2).reshape(2 * S * 8, -1))   # [((s, h), j), (r, i)]
            prm = K.param_fields(self.p[d.pbase:d.pbase + 64 * d.cout64])
            self.cache[i] = (gather_plan(d), Wd, kk, tt, prm)
        return self.cache[i]

    def conv(self, act, i, d, literal=False):
        (pos, val), Wd, kk, tt, (bias, m0, sh, dd) = self._pass_data(i, d)
        N, P, S, Co = act.shape[0], d.Hout * d.Wout, pos.shape[1], 64 * d.cout64
        if literal:
            x = gather_window(act[:, d.in_buf], d)                                 # [N, P, S, 16]
            acc = pe_literal(x.reshape(N, P, 2 * S, 8), kk, tt).reshape(N, P, Co)
        else:
            x = lanes16(act[:, d.in_buf][:, pos]) * val[None, :, :, None]           # [N, P, S, 16]
            acc = (x.reshape(N * P, S * 16).astype(np.float32) @ Wd).astype(np.int64).reshape(N, P, Co)
        assert np.abs(acc).max() < ACC_LIM, "20-b accumulator overflow"
        v = np.where(dd == 1, -acc, acc) + bias
        assert np.abs(v).max() < V_LIM, "20-b PPU v overflow"
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
        p = np.clip(rq(f.sum((2, 3)), np.int64(h.pool_m0), np.int64(h.pool_sh)), 0, 127)
        W = K.fc_weights(self.we[h.wbase:h.wbase + h.cin8 * h.ncls]).reshape(h.cin8, h.ncls, 8)
        W = W.transpose(1, 0, 2).reshape(h.ncls, 8 * h.cin8)
        bias = K.param_fields(self.p[h.pbase:h.pbase + h.ncls])[0]
        acc = p @ W.T + bias
        assert np.abs(acc).max() < 2 ** 31
        return acc, p

    def run(self, act, snap=True, literal=False):
        snaps = []
        for i, d in enumerate(self.convs):
            self.conv(act, i, d, literal)
            if snap:
                snaps.append(act[:, d.out_buf].copy())
        logits, p = self.run_head(act)
        return logits, snaps, p


def gather_window(buf, d):
    """Array inputs [N, P, S, 16] through the v3 kw window (8 raw 128-b words; shift, slot reads, lane mask)."""
    w = window_plan(d)
    N, T, S = buf.shape[0], w["base"].shape[0], w["base"].shape[1]
    W = np.zeros((N, T, 8, 2), np.uint64)
    out = np.zeros((N, T, S, 8, 16), np.int8)
    j = np.arange(8)
    for s in range(S):
        if w["shift"][s]:
            W = np.concatenate([W[:, :, 1:], np.zeros((N, T, 1, 2), np.uint64)], 2)
        else:
            W = np.zeros_like(W)
        idx = w["base"][:, s, None] + j
        rd = w["read"][:, s]
        assert (idx[rd] >= 0).all() and (d.in_base + (idx[rd] >> 3) < DEPTH).all(), "window read outside the buffer"
        pos = flat(np.where(rd, idx, 0), d.in_base)
        W = np.where(rd[None, :, :, None], buf[:, pos], W)
        out[:, :, s] = lanes16(W) * w["lane"][None, :, s, :, None]
    return out.transpose(0, 1, 3, 2, 4).reshape(N, T * 8, S, 16)


# ---- cycle model (MODEL, not measured) -----------------------------------------------------------------------
def cycles(images):
    """Per pass: tiles x max(S, drain) + 64-cycle param load per og; S = k*k*ceil(cin8/2) steps per tile, drain = 32
    cycles (one pair word = 2 columns per cycle; 64 for RAW16 / RES_R: 2 bank accesses per pair word).  Head as v2."""
    prog = read_program(images["desc"])
    out = []
    for d in prog[:-1]:
        tiles = d.Hout * d.Wout // 8 * d.cout64
        drain = 64 if d.mode in (RAW16, RES_R) else 32
        out.append(tiles * max(d.k * d.k * cinp(d.cin8), drain) + 64 * d.cout64)
    h = prog[-1]
    out.append(h.cin8 * (h.Hin * h.Win + h.ncls) + 16)
    return out


def act_reads(images):
    from .layout import act_reads as ar
    return [ar(d) for d in read_program(images["desc"])[:-1]]
