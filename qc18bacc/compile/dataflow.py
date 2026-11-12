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
Asserts logits == golden logits (torch.equal) per batch (--golden p2: qc18bacc.golden_p2.IntBin2, default; intbin:
qc18b.int_bin.IntBin).  p2: the identity-block c2 residual is rs = program.idm_shift(relu(s_in), j), j in {0, -1}.
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


GROUP_PLANE = lambda h, g: 4 * h + g          # stem packing: group g of cycle h carries this plane (test hook)


def pe_stem_packed(p, planes, W):
    """v1.1 stem packing: the KB = 36 bytes of a chunk are 9 taps x 4 channel groups; in stem mode group g of cycle h
    carries bit-plane 4h + g of the 8 (padded) image channels, every group holds the same 9 tap codes, and the PE
    popcounts the 4 groups separately: sum_{g,i} = u_{g,i} - nneg_g, acc_i += sum_g (+/-) (sum_{g,i} << g) << 4h
    (plane 7 = group 3 of h = 1 negative, two's-complement MSB), mod 2^20.  2 cycles per tile (no plane skip).
    Returns acc [N, L, Cout] and items [N, Tp] (= 2)."""
    assert p.cinp == 8 and p.nchunk == 1 and len(planes) == 8
    N = planes[0][0].shape[0]
    L, Tp = p.Hout * p.Wout, p.tiles_px
    pos = W.pos[0].view(9, P.CH, -1)                                                   # [tap, 32 ch, Cout]
    neg = W.neg[0].view(9, P.CH, -1)
    assert not pos[:, 8:].any() and not neg[:, 8:].any(), "stem weights outside group 0"
    acc = torch.zeros(N, L, p.cout, dtype=torch.int64, device=pos.device)
    exact = torch.zeros_like(acc)
    for h in range(2):
        a = torch.cat([patches(planes[GROUP_PLANE(h, g)][0], p)[:, :, 0].view(N, L, 9, P.CH)[..., :8]
                       for g in range(4)], -1)
        a = a.reshape(N, L, 9 * P.CH)                                                  # byte j = tap * 4 + g
        tot = 0
        for g in range(4):
            Wp = torch.zeros(9, 4, 8, p.cout, device=pos.device)
            Wn = torch.zeros_like(Wp)
            Wp[:, g], Wn[:, g] = pos[:, :8], neg[:, :8]                                # same 9 tap codes in group g
            u = torch.matmul(a, Wp.view(9 * P.CH, -1)) + torch.matmul(1 - a, Wn.view(9 * P.CH, -1))
            ui = u.round().long()
            # the 1 - a term counts only group-g bytes because Wn is zero elsewhere
            assert torch.equal(ui.double(), u.double()) and (ui >= 0).all() and (ui <= 2 * 9).all(), "group popcount"
            nn = Wn.sum((0, 1, 2)).long()
            sg = (ui - nn) << g
            tot = tot + (-sg if 4 * h + g == 7 else sg)
            assert planes[4 * h + g][1] == (4 * h + g == 7)
        v = tot << (4 * h)
        exact += v
        acc = (acc + v) & MASK
    acc = torch.where(acc >= 1 << (P.ACC_W - 1), acc - (1 << P.ACC_W), acc)
    assert torch.equal(acc, exact), "ACC_W wrap"
    return acc, torch.full((N, Tp), 2, dtype=torch.int64, device=acc.device)


def col(t):
    return torch.as_tensor(t).to(torch.int64)


def fz(p):
    """fused-lane parameters of a v1.1 pass on the device."""
    return {k: (col(v).to(p.p["dev"]) if torch.is_tensor(v) else v) for k, v in p.p["f"].items()}


def do_pass(prog, p, bf, Ws, dev, stats):
    """one pass of the program on buffers bf (reads its source / S, writes its destinations)."""
    p.p["dev"] = dev
    dv = lambda k: col(p.p[k]).to(dev)
    L, Li = p.Hout * p.Wout, p.Hin * p.Win
    if p.k:
        if p.inb == 8:
            C = 8 if p.src == "IMG" else p.cin
            planes = [(nchw(bf.read(p.src, Li, C, plane=b), p.Hin, p.Win).float(), b == 7) for b in range(8)]
        else:
            planes = [(nchw(bf.read(p.src, Li, p.cin), p.Hin, p.Win).float(), False)]
        if p.p.get("pack"):
            acc, items = pe_stem_packed(p, planes, Ws[p.name])
        else:
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
        if p.p["res"] == "idm" and "idm_j" in p.p:                                 # p2: shift, no multiplier
            r = P.idm_shift(sin.clamp(min=0), p.p["idm_j"])
            obs(p.name + ".idm", r)
        elif p.p["res"] == "idm":
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
        if "f" in p.p:
            y, _ = P.lane_f(s, fz(p))                                                  # input ReLU, pre-clamp, u8
        else:
            y, _ = P.lane_w(s.clamp(min=0), dv("m0"), dv("sh"), mode="u8")
        for b in range(8):
            bf.write("HQ", (y >> b) & 1, plane=b)
    elif p.kind == "wc1":
        if "f" in p.p:
            y, _ = P.lane_f(x_, fz(p))
        else:
            y, _ = P.lane_w(x_ + dv("bias"), dv("m0"), dv("sh"), mode="u8")
        for b in range(8):
            bf.write("Z", (y >> b) & 1, plane=b)
    elif p.kind == "wsc":
        if "f" in p.p:
            r, _ = P.lane_f(x_, fz(p))
        else:
            r, _ = P.lane_w(x_ + dv("bias"), dv("m0"), dv("sh"), mode="r")
        obs(p.name, r)
        if p.p.get("r1"):
            bf.write("S", r)                                                         # 17 b: one entry
        else:
            bf.write("S", r & 0xFFFF)                                                # lo 16 b
            bf.write("S", r >> 16, off=L * p.cout)                                   # hi (signed)
    elif p.kind == "wc2":
        sc = next(q for q in prog.passes if q.block == p.block and q.kind == "wsc")
        r = bf.read("S", L, p.cout)
        if not sc.p.get("r1"):
            r = r + (bf.read("S", L, p.cout, off=L * p.cout) << 16)
        if "f" in p.p:
            ys, b = P.lane_f(x_, fz(p), r=r, t=dv("T"))
        else:
            ys, b = P.lane_w(x_ + dv("bias"), dv("m0"), dv("sh"), r=r, t=dv("T"))
        bf.write("S", ys)
        bf.write("B1", b.long())
    else:
        raise ValueError(p.kind)


@torch.no_grad()
def run(prog, x, dev="cuda", Ws=None):
    """x: uint8 NHWC images.  Returns logits, {pass: items [N, Tp] (numpy)}."""
    N = x.shape[0]
    bf = Bufs(N, dev)
    Ws = Ws if Ws is not None else {p.name: PEWeights(p, dev) for p in prog.passes if p.k}
    load_image(prog, bf, x, dev)
    stats = {}
    for p in prog.passes:
        do_pass(prog, p, bf, Ws, dev, stats)
    return head(prog, bf, dev), stats


def head(prog, bf, dev):
    h = prog.head
    last = prog.passes[-1]
    s = bf.read("S", last.Hout * last.Wout, last.cout)
    pq, _ = P.lane_w(s.clamp(min=0).sum(1), col(h["pool_m0"]).to(dev), col(h["pool_sh"]).to(dev), mode="u8")
    return (igemm(F.linear, pq, h["fW8"]) + h["fbq"]).double() * h["fscale"]


def load_image(prog, bf, x, dev):
    lut = prog.lut.to(dev)
    xi = x.permute(0, 3, 1, 2).long()                                                  # [N, 3, 32, 32]
    q = torch.stack([lut[c][xi[:, c]] for c in range(3)], 1)
    q8 = F.pad(q, (0, 0, 0, 0, 0, 5)).flatten(2).transpose(1, 2) & 0xFF                # [N, L, 8] two's complement
    for b in range(8):
        bf.write("IMG", (q8 >> b) & 1, plane=b)


ENT = {}


def _entries(T, base, dev):
    """per tile: buffer entry indices of its footprints {(t, 'ar' | 'dr' | 'wr', buf): LongTensor} (cached)."""
    key = id(T)
    if key in ENT:
        return ENT[key]
    nb = {k: -(-P.BUFS[k][0] // 64) for k in P.BUFS}
    out = {}
    for t, d in enumerate(T):
        for f in ("ar", "dr", "wr"):
            b = np.array(sorted(d[f]), dtype=np.int64)
            for buf in P.BUFS:
                m = b[(b >= base[buf]) & (b < base[buf] + nb[buf])] - base[buf]
                if len(m):
                    out[t, f, buf] = torch.as_tensor((m[:, None] * 64 + np.arange(64)).ravel(), device=dev)
    ENT[key] = out
    return out


@torch.no_grad()
def replay(prog, x, T, base, tim, dev="cuda", Ws=None):
    """Execute the program on ONE image tile by tile in the scheduled order (cycles.list_schedule times tim[f][tile]):
    events sorted by time (writes before reads at equal times): array read at st (snapshot of the tile's input rows,
    every other entry zeroed), drain read at ds (snapshot of its S entries), write at de (pecmp: capture) = the pass
    computed from the tile's snapshots, only the tile's own output entries written to the shared buffers.  A read of a
    stale / not yet written / clobbered entry changes the values (unwritten entries assert).  Returns the logits."""
    Ws = Ws if Ws is not None else {p.name: PEWeights(p, dev) for p in prog.passes if p.k}
    bf = Bufs(1, dev)
    load_image(prog, bf, x, dev)
    ent = _entries(T, base, dev)
    ev = []
    for t, d in enumerate(T):
        if d["arr"]:
            ev.append((int(tim["st"][t]), 1, t, "a"))
        if d["dr"]:
            ev.append((int(tim["ds"][t]), 1, t, "d"))
        ev.append((int(tim["de"][t]), 0, t, "w"))
    ev.sort()
    snap = {}
    obs0 = dict(OBS)
    for _, _, t, k in ev:
        d = T[t]
        p = prog.passes[d["pi"]]
        if k == "a":
            if p.src == "IMG":
                snap[t, "a"] = bf.b["IMG"].clone()
            else:
                z = torch.zeros_like(bf.b[p.src])
                e = ent[t, "ar", p.src]
                z[:, e] = bf.b[p.src][:, e]
                snap[t, "a"] = z
        elif k == "d":
            z = torch.zeros_like(bf.b["S"])
            e = ent[t, "dr", "S"]
            z[:, e] = bf.b["S"][:, e]
            snap[t, "d"] = z
        else:
            sb = Bufs(1, dev)
            if (t, "a") in snap:
                sb.b[p.src] = snap.pop((t, "a"))
            if (t, "d") in snap:
                sb.b["S"] = snap.pop((t, "d"))
            do_pass(prog, p, sb, Ws, dev, {})
            for buf in P.BUFS:
                e = ent.get((t, "wr", buf))
                if e is not None:
                    bf.b[buf][:, e] = sb.b[buf][:, e]
    OBS.clear()
    OBS.update(obs0)                     # tile replays compute whole passes on partial snapshots: not observations
    return head(prog, bf, dev)


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
    log(f"{prog.run}: dataflow logits == {type(net).__name__} logits (torch.equal) on val[:{n}]: PASS; "
        f"acc {100 * correct / n:.2f} %")
    return st, correct


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--v", type=int, default=11, choices=(1, 11))
    ap.add_argument("--golden", default="p2", choices=P.GOLDENS)
    a = ap.parse_args()
    prog, net, val = P.build_program(a.ckpt, v=a.v, golden=a.golden)
    run_val(prog, net, val, a.n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
