"""Bit-exact golden model of QC18-ACC v4 (16 pixel rows): v3 arithmetic (compile3.golden.Golden3: 20-b PE
accumulators, two blocks per step, 20-b PPU v, head) executed on the v4 memory images: the same descriptor / weight /
param images as v3, activation buffers of 16 banks x 256 x 128 b (uint64 [N, 3, 4096, 2], flat position
bank * 256 + address).  literal=True: per-block two-term path on inputs gathered through the 16-slot kw window
(gather_window), i.e. the RTL data path.  Cycle MODEL with 16 or 32 PPU lanes (`cycles`).
"""
import numpy as np

from qc18acc.compile.golden import pe_literal, rq
from qc18acc.compile.program import RAW16, RELU, RES_ID, RES_R, read_program
from qc18acc.compile3 import golden as G3

from .layout import DEPTH, ROWS, cinp, flat, gather_plan, join16, read_tensor, split16, window_plan, write_tensor

lanes16 = G3.lanes16


class Golden4(G3.Golden3):
    """Golden3 with the v4 layout (gather plan / tensor read / write)."""

    def _pass_data(self, i, d):
        if i not in self.cache:
            pd = super()._pass_data(i, d)
            self.cache[i] = (gather_plan(d),) + pd[1:]
        return self.cache[i]

    def conv(self, act, i, d, literal=False):
        (pos, val), Wd, kk, tt, (bias, m0, sh, dd) = self._pass_data(i, d)
        N, P, S, Co = act.shape[0], d.Hout * d.Wout, pos.shape[1], 64 * d.cout64
        if literal:
            x = gather_window(act[:, d.in_buf], d)
            acc = pe_literal(x.reshape(N, P, 2 * S, 8), kk, tt).reshape(N, P, Co)
        else:
            x = lanes16(act[:, d.in_buf][:, pos]) * val[None, :, :, None]
            acc = (x.reshape(N * P, S * 16).astype(np.float32) @ Wd).astype(np.int64).reshape(N, P, Co)
        assert np.abs(acc).max() < G3.ACC_LIM, "20-b accumulator overflow"
        v = np.where(dd == 1, -acc, acc) + bias
        assert np.abs(v).max() < G3.V_LIM, "20-b PPU v overflow"
        y = rq(v, m0, sh)
        y = np.moveaxis(y.reshape(N, d.Hout, d.Wout, Co), 3, 1)
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
        from qc18acc.compile import codes as K
        f = read_tensor(act[:, h.in_buf], h.in_lay, h.in_base, 8 * h.cin8, h.Hin, h.Win).astype(np.int64)
        p = np.clip(rq(f.sum((2, 3)), np.int64(h.pool_m0), np.int64(h.pool_sh)), 0, 127)
        W = K.fc_weights(self.we[h.wbase:h.wbase + h.cin8 * h.ncls]).reshape(h.cin8, h.ncls, 8)
        W = W.transpose(1, 0, 2).reshape(h.ncls, 8 * h.cin8)
        bias = K.param_fields(self.p[h.pbase:h.pbase + h.ncls])[0]
        acc = p @ W.T + bias
        assert np.abs(acc).max() < 2 ** 31
        return acc, p


def gather_window(buf, d):
    """Array inputs [N, P, S, 16 lanes] through the v4 kw window (16 raw 128-b slots; shift, slot reads, row mask)."""
    w = window_plan(d)
    N, T, S = buf.shape[0], w["base"].shape[0], w["base"].shape[1]
    W = np.zeros((N, T, ROWS, 2), np.uint64)
    out = np.zeros((N, T, S, ROWS, 16), np.int8)
    j = np.arange(ROWS)
    for s in range(S):
        if w["shift"][s]:
            W = np.concatenate([W[:, :, 1:], np.zeros((N, T, 1, 2), np.uint64)], 2)
        else:
            W = np.zeros_like(W)
        idx = w["base"][:, s, None] + j
        rd = w["read"][:, s]
        assert (idx[rd] >= 0).all() and (d.in_base + (idx[rd] >> 4) < DEPTH).all(), "window read outside the buffer"
        pos = flat(np.where(rd, idx, 0), d.in_base)
        W = np.where(rd[None, :, :, None], buf[:, pos], W)
        out[:, :, s] = lanes16(W) * w["lane"][None, :, s, :, None]
    return out.transpose(0, 1, 3, 2, 4).reshape(N, T * ROWS, S, 16)


# ---- cycle model (MODEL, not measured) -----------------------------------------------------------------------
def cycles(images, lanes=32):
    """Per pass: tiles x max(S, drain) + 64-cycle param load per og; tiles = H_out W_out / 16 x cout64,
    S = k*k*ceil(cin8/2) steps per tile; drain of a 16 x 64 tile (1024 accumulators): 32 lanes = 2 pair words per
    cycle -> 32 cycles, 16 lanes -> 64 cycles; RAW16 / RES_R take 2 cycles per pair word (x2).  Head: per channel
    group max(pool rows + 1, ncls) cycles (pool of group cb + 1 overlapped with the FC of group cb) + 32."""
    prog = read_program(images["desc"])
    out = []
    for d in prog[:-1]:
        tiles = d.Hout * d.Wout // ROWS * d.cout64
        drain = (1024 // lanes) * (2 if d.mode in (RAW16, RES_R) else 1)
        out.append(tiles * max(d.k * d.k * cinp(d.cin8), drain) + 64 * d.cout64)
    h = prog[-1]
    out.append(h.cin8 * max(h.Hin * h.Win // ROWS + 1, h.ncls) + 32)
    return out


def act_reads(images):
    from .layout import act_reads as ar
    return [ar(d) for d in read_program(images["desc"])[:-1]]
