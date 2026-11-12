"""Bit-exact dataflow model of QC18B-ACC executing a program (qc18bacc.compile.program) the way the hardware does:

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.dataflow RUN/best.pt [--n 500]

Buffers are flat per-image arrays (program.BUFS), maps stored row-major, one entry per (pixel, channel), address
pix * C + c (int8 maps: one bit-plane after the other); every pass reads its source buffer and writes its destination
buffers, the stream S in place (c2 drains read s_in / r at the addresses they write).
Array (per pass, tiles of 16 output pixels (raster) x 64 output channels; all tiles are computed together, the tile
structure enters through the per-tile skip decision and the per-tile item counts):
  chunk item = (chunk, plane), plane-major order.  3x3: chunk c = 9 taps x 32 input channels 32c..32c+31 (byte j = tap*4 +
  group); 1x1: one chunk = 36 groups of the centre tap.  Activation bits of the chunk patch a (288 b per pixel), the PE
  weights are the program's 8-b codes decoded through DEC to the 10-b PE code and placed per lane (lane i, byte j,
  bit (i + k) mod 8 gets trit t).  Popcount form: u_i = #{terms: t = +1 and a = 1} + #{terms: t = -1 and a = 0}
  (= popcount of x = (t != 0) & (a ^ (t == -1))), checked in [0, 2 KB]; sum_i = u_i - nneg (nneg = #(t == -1) of the
  PE column); acc = acc +/- (sum << plane) mod 2^20 (two's-complement MSB plane: -); final acc sign-extended from 20 b
  must equal the exact integer sum (ACC_W wrap check).
  int8 inputs: an item whose 16-pixel x 288-bit patch of that plane is all zero is skipped (its sum is asserted to be 0);
  the stem's 8 planes are never skipped.  Executed items per (image, pixel tile) are recorded (same for the Cout/64
  channel tiles of a pixel tile).
PPU: acc' = sgn acc (+ int bias pre-add for the stem / block 6); lanes = program.lane_s8 / lane_w / compare acc' >= T2.
Head: relu(s_7) summed over the 16 positions, wide lane (pool_m, clamp [0, 127]), FC int8 (int32 acc + bias) x float scale.
Asserts logits == IntBin logits (torch.equal) per batch.
"""
import argparse
import sys

import numpy as np
import torch
import torch.nn.functional as F

from qc.structure import expand
from qc18.int8 import igemm

from . import program as P

MASK = (1 << P.ACC_W) - 1
OBS = {}                  # observed max |r| (sc output / idm rs) per pass over every image run (diagnostic)


def obs(name, t):
    OBS[name] = max(OBS.get(name, 0), int(t.abs().max()))
PLANAR = ("HQ", "Z", "IMG")


class Bufs:
    def __init__(self, N, dev):
        self.b = {k: torch.full((N, n), -(1 << 40), dtype=torch.int64, device=dev) for k, (n, _) in P.BUFS.items()}

    def write(self, name, t, plane=None, off=0):
        """t: [N, L, C] (pixel-major) -> entries off + plane * L C + pix C + c."""
        N, L, C = t.shape
        bits = P.BUFS[name][1]
        if bits == 1:
            assert ((t == 0) | (t == 1)).all()
        else:
            assert (t.abs() < 2 ** (bits - 1)).all(), f"{name}: value outside {bits} b"
        o = off + (0 if plane is None else plane * L * C)
        assert o + L * C <= P.BUFS[name][0]
        self.b[name][:, o:o + L * C] = t.reshape(N, -1)

    def read(self, name, L, C, plane=None, off=0):
        o = off + (0 if plane is None else plane * L * C)
        t = self.b[name][:, o:o + L * C].reshape(-1, L, C)
        assert (t > -(1 << 40)).all(), f"{name}: read of an unwritten entry"
        return t


def nchw(t, H, W):
    return t.view(t.shape[0], H, W, t.shape[2]).permute(0, 3, 1, 2)


class PEWeights:
    """per pass: Wpos / Wneg [nchunk, 288, Cout] (float32 0/1) and nneg [nchunk, Cout] from the 8-b codes."""

    def __init__(self, p, dev):
        Md = expand(torch.as_tensor(P.decode(p.codes), dtype=torch.float64), P.B)      # [Cout, Cb * 8], lane x bit
        if p.k == 3:
            M = Md.view(p.cout, 9, p.cinp)
            M = F.pad(M, (0, p.nchunk * P.CH - p.cinp)).view(p.cout, 9, p.nchunk, P.CH).permute(2, 0, 1, 3)
            M = M.reshape(p.nchunk, p.cout, 9 * P.CH)
        else:
            M = F.pad(Md, (0, P.KB * P.B - p.cinp))[None]
        assert M.shape[-1] == P.KB * P.B
        self.pos = (M == 1).float().transpose(1, 2).contiguous().to(dev)
        self.neg = (M == -1).float().transpose(1, 2).contiguous().to(dev)
        nn = self.neg.sum(1).long()                                                    # [nchunk, Cout]
        g = nn.view(nn.shape[0], -1, P.B)
        assert (g == g[..., :1]).all(), "nneg differs inside a PE column"
        self.nneg = nn


def patches(a, p):
    """a: [N, cinp, H, W] (one bit-plane, float) -> [N, L, nchunk, 288] chunk patches."""
    N = a.shape[0]
    if p.k == 3:
        u = F.unfold(a, 3, padding=p.pad, stride=p.stride)                             # [N, cinp * 9, L]
        u = u.view(N, p.cinp, 9, -1).permute(0, 3, 2, 1)                              # [N, L, 9, cinp]
        u = F.pad(u, (0, p.nchunk * P.CH - p.cinp)).view(N, -1, 9, p.nchunk, P.CH).permute(0, 1, 3, 2, 4)
        return u.reshape(N, -1, p.nchunk, 9 * P.CH)
    u = a[:, :, ::p.stride, ::p.stride].flatten(2).transpose(1, 2)                   # [N, L, cinp]
    return F.pad(u, (0, P.KB * P.B - p.cinp))[:, :, None]


def pe_array(p, planes, skip, W):
    """planes: list of (bit map [N, cinp, H, W] float, neg).  Returns acc [N, L, Cout] (int64, raw M x), items [N, Tp]."""
    N = planes[0][0].shape[0]
    L, Tp = p.Hout * p.Wout, p.tiles_px
    acc = torch.zeros(N, L, p.cout, dtype=torch.int64, device=W.pos.device)
    exact = torch.zeros_like(acc)
    items = torch.zeros(N, Tp, dtype=torch.int64, device=acc.device)
    for pl, (a_map, neg) in enumerate(planes):                                        # plane-major
        pt = patches(a_map, p)
        for c in range(p.nchunk):
            a = pt[:, :, c]
            ex = a.reshape(N, Tp, P.ROWS * a.shape[-1]).any(-1) if skip else torch.ones(N, Tp, dtype=torch.bool,
                                                                                         device=a.device)
            u = torch.matmul(a, W.pos[c]) + torch.matmul(1 - a, W.neg[c])
            ui = u.round().long()
            assert torch.equal(ui.double(), u.double()) and (ui >= 0).all() and (ui <= 2 * P.KB).all(), "popcount"
            s = ui - W.nneg[c]
            exm = ex.repeat_interleave(P.ROWS, 1)[..., None]
            assert (s.masked_select(~exm) == 0).all(), "skipped item with a nonzero sum"
            v = (s * exm) << pl
            v = -v if neg else v
            exact += v
            acc = (acc + v) & MASK
            items += ex
    acc = torch.where(acc >= 1 << (P.ACC_W - 1), acc - (1 << P.ACC_W), acc)
    assert torch.equal(acc, exact), "ACC_W wrap"
    return acc, items


def col(t):
    return torch.as_tensor(t).to(torch.int64)


@torch.no_grad()
def run(prog, x, dev="cuda", Ws=None):
    """x: uint8 NHWC images.  Returns logits, {pass: items [N, Tp] (numpy)}."""
    N = x.shape[0]
    bf = Bufs(N, dev)
    Ws = Ws if Ws is not None else {p.name: PEWeights(p, dev) for p in prog.passes if p.k}
    lut = prog.lut.to(dev)
    xi = x.permute(0, 3, 1, 2).long()                                                  # [N, 3, 32, 32]
    q = torch.stack([lut[c][xi[:, c]] for c in range(3)], 1)
    q8 = F.pad(q, (0, 0, 0, 0, 0, 5)).flatten(2).transpose(1, 2) & 0xFF                # [N, L, 8] two's complement
    for b in range(8):
        bf.write("IMG", (q8 >> b) & 1, plane=b)
    stats = {}
    for p in prog.passes:
        dv = lambda k: col(p.p[k]).to(dev)
        L, Li = p.Hout * p.Wout, p.Hin * p.Win
        if p.k:
            if p.inb == 8:
                C = 8 if p.src == "IMG" else p.cin
                planes = [(nchw(bf.read(p.src, Li, C, plane=b), p.Hin, p.Win).float(), b == 7) for b in range(8)]
            else:
                planes = [(nchw(bf.read(p.src, Li, p.cin), p.Hin, p.Win).float(), False)]
            acc, items = pe_array(p, planes, p.inb == 8 and p.kind != "stem", Ws[p.name])
            stats[p.name] = items.cpu().numpy()
            x_ = acc * col(p.sgn).to(dev)                                               # PPU input: acc' = sign(g) acc
        if p.kind == "stem":
            ys, b = P.lane_s8(x_ + dv("bias"), dv("m"), dv("sel"), t=dv("T"))
            bf.write("S", ys)
            bf.write("B1", b.long())
        elif p.kind == "bc1":
            bf.write("B2", (x_ >= dv("T")).long())
        elif p.kind == "bsc":
            r, _ = P.lane_s8(x_, dv("m"), dv("sel"), dv("h"), rmode=True)
            obs(p.name, r)
            bf.write("S", r)
        elif p.kind == "bc2":
            sin = bf.read("S", L, p.cout)                                                # in place: same addresses
            if p.p["res"] == "idm":
                r = P.lane_s8_rq(sin.clamp(min=0), dv("idm_m"), dv("idm_sel"))
                obs(p.name + ".idm", r)
            else:
                r = sin
            t = None if p.p["T"] is None else dv("T")
            ys, b = P.lane_s8(x_, dv("m"), dv("sel"), dv("h"), r, t)
            bf.write("S", ys)
            if b is not None:
                bf.write("B1", b.long())
        elif p.kind == "hm":
            s = bf.read("S", L, p.cin)
            y, _ = P.lane_w(s.clamp(min=0), dv("m0"), dv("sh"), mode="u8")
            for b in range(8):
                bf.write("HQ", (y >> b) & 1, plane=b)
        elif p.kind == "wc1":
            y, _ = P.lane_w(x_ + dv("bias"), dv("m0"), dv("sh"), mode="u8")
            for b in range(8):
                bf.write("Z", (y >> b) & 1, plane=b)
        elif p.kind == "wsc":
            r, _ = P.lane_w(x_ + dv("bias"), dv("m0"), dv("sh"), mode="r")
            obs(p.name, r)
            bf.write("S", r & 0xFFFF)                                                    # lo 16 b
            bf.write("S", r >> 16, off=L * p.cout)                                       # hi (signed)
        elif p.kind == "wc2":
            r = bf.read("S", L, p.cout) + (bf.read("S", L, p.cout, off=L * p.cout) << 16)
            ys, b = P.lane_w(x_ + dv("bias"), dv("m0"), dv("sh"), r=r, t=dv("T"))
            bf.write("S", ys)
            bf.write("B1", b.long())
        else:
            raise ValueError(p.kind)
    h = prog.head
    last = prog.passes[-1]
    s = bf.read("S", last.Hout * last.Wout, last.cout)
    pq, _ = P.lane_w(s.clamp(min=0).sum(1), col(h["pool_m0"]).to(dev), col(h["pool_sh"]).to(dev), mode="u8")
    logits = (igemm(F.linear, pq, h["fW8"]) + h["fbq"]).double() * h["fscale"]
    return logits, stats


@torch.no_grad()
def run_val(prog, net, val, n=500, bs=100, dev="cuda", log=print):
    """dataflow on val[:n] in batches; asserts logits == IntBin logits.  Returns {pass: items [n, Tp]}, n_correct."""
    xv, yv = val
    Ws = {p.name: PEWeights(p, dev) for p in prog.passes if p.k}
    st, correct = {}, 0
    for i in range(0, n, bs):
        xb = xv[i:min(i + bs, n)]
        lg, s = run(prog, xb, dev, Ws)
        ref = net(xb)
        assert torch.equal(lg, ref), f"dataflow logits != IntBin logits (val[{i}:{i + len(xb)}])"
        correct += int((lg.argmax(1) == yv[i:i + len(xb)]).sum())
        for k, v in s.items():
            st.setdefault(k, []).append(v)
    st = {k: np.concatenate(v) for k, v in st.items()}
    log(f"{prog.run}: dataflow logits == IntBin logits (torch.equal) on val[:{n}]: PASS; acc {100 * correct / n:.2f} %")
    return st, correct


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--n", type=int, default=500)
    a = ap.parse_args()
    prog, net, val = P.build_program(a.ckpt)
    run_val(prog, net, val, a.n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
