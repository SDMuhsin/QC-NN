"""Accelerator workload of the integer qc18b network (golden model qc18b.int_bin.IntBin), measurement only:

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.workload RUN/best.pt [--n 2000] [--out FILE]

Setup.  build / Folded (qc18b.verify_bin), calibration exactly as qc18b.int_bin.main (float_trace on train[:2000] in
chunks of 500 -> IntBin).  Measured on the first --n VAL images only (never test).  An instrumented copy of the IntBin
forward (same integer ops, using IntBin's own weights / multipliers / thresholds) records every tensor; its logits are
asserted bit-exact (torch.equal) against IntBin.__call__ on every batch before anything is reported.

[1] conv workload (one row per conv: stem, blocks.i.c1 / c2 / sc):
  Cin Cout k s      real input / output channels, kernel, stride.   HoxWo  output positions.
  in-b              input activation bits: 8 (stem: signed int8 image; fp block c1/sc: relu int8 hq, c2: relu int8 z), 1 (binary).
  exec MAC/img      nonzero +-1 terms of the QC matrix on the real input channels x Hout*Wout (= qc18b.opcount terms;
                    zero-padding at borders not skipped).
  slot MAC/img      all b x b = 8x8 blocks of the padded GEMM matrix (zero blocks included) x 16 (2 slots x 8 rows) x Hout*Wout:
                    the work of a fixed 2-slot-per-block datapath.   fill = exec / slot.
[2] accumulator acc' = sign(g) M x (before bias / requant):
  bound             worst case max_c max(|lo_c|, |hi_c|), lo/hi = sum over the row of min/max(w*in_lo, w*in_hi) for the input
                    range (stem [-127,127], hq / z [0,127], binary {0,1}); padded channels (always 0) excluded.
  obs               observed max |acc'| over the images.   bits = signed two's-complement width for magnitude V: bitlen(V) + 1.
[3] int8 tensors of the fp block (block 6) and the stem input:  q (stem input, signed; bit planes of the 8-bit two's complement
  'tc' and of sign-magnitude 'sm' = |q| planes 0..6 + sign plane), hq (relu-requant c1/sc input), z (c1 output, c2 input).
  max (max |value|), %zero (elements == 0).  Words = 16 consecutive raster pixels (h*W + w) x 8 consecutive channels (stem:
  3 channels zero-padded to 8 as in hardware).  P(b=0) = fraction of words whose bit plane b is all zero; planes/word = mean
  number of planes that are not all zero (the bit-serial cycles per word with zero-plane skipping).
[4] requant multipliers (m0, sh) of IntBin (qc18.int8.fixmul: m0 31-bit, y = (x m0 + 2^(sh-1)) >> sh): per channel the minimal
  bit width of a non-negative integer m' such that, with some shift sh' >= 0 (rounding term 2^(sh'-1), 0 for sh' = 0),
  (x m' + 2^(sh'-1)) >> sh' == (x m0 + 2^(sh-1)) >> sh for EVERY integer x of the worst-case domain:
     stem_m, fp c1m / c2m / scm: [lo_c, hi_c] of [2] + the int32 bias (requant input is acc' + bias);
     binary c2m / scm: [lo_c, hi_c] of [2] (bias added after);  idm, hm: relu'd int16 stream [0, 32767];
     pool_m: sum of 16 relu'd int16 values [0, 16*32767].
  Exact interval method (no sampling): for each sh', every x gives a linear constraint on m', the intersection [L, U] is
  computed in int64 over all x; minimal bits = min over sh' of bitlen(L) where L <= U.  'unclamped' = the raw requant;
  'clamped' (hm, c1m, pool_m, which are clamped to [0, 127] in IntBin) = equality after that clamp only.  max / median over channels.
[5] residual stream s_k (stem output s0, block outputs s1..s8): observed max |s_k| before the int16 clamp, saturations (|s| > 32767).
[6] weight codes (QC coefficients C of M, verify_bin.fold_conv / qc.structure.decompose; the integer weight sign(g) M is not
  itself QC when only some rows of a block flip, so the per-output-channel sign(g) is a separate 1 b/channel, listed): per 8x8 block the number of
  nonzero terms (0 / 1 / 2) per layer and network-wide; distinct slot codes (shift, trit=+-1) and distinct block codes (the set
  of (shift, trit) pairs of a block, empty included); code storage = blocks x 10 b (2 slots x (valid + 3-bit shift + sign));
  FC int8 weights 100 x 512 x 8 b (+ int32 bias 100 x 32 b).
[7] binary tensors: fraction of ones of b1 (c1/sc input) and b2 (c1 output, c2 input) per binary block.
"""
import argparse
import os
import statistics
import sys

import torch
import torch.nn.functional as F

from qc.structure import to_matrix
from qc18.int8 import requant, igemm
from qc18b import data
from qc18b.int_bin import IntBin, float_trace, Q16
from qc18b.verify_bin import Folded, build

RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
B = 8


def bitlen(v):
    return int(v).bit_length()


class Stats:
    def __init__(self):
        self.accmax, self.hw, self.words, self.tens, self.ones, self.smax, self.sat = {}, {}, {}, {}, {}, {}, {}

    def acc(self, name, a):
        m = a.abs().amax((0, 2, 3))
        self.accmax[name] = torch.maximum(self.accmax[name], m) if name in self.accmax else m
        self.hw[name] = tuple(a.shape[2:])

    def stream(self, k, s):
        self.smax[k] = max(self.smax.get(k, 0), int(s.abs().max()))
        self.sat[k] = self.sat.get(k, 0) + int((s.abs() > Q16).sum())

    def binary(self, name, t):
        o = self.ones.setdefault(name, [0, 0])
        o[0] += int(t.sum())
        o[1] += t.numel()

    def int8(self, name, t, nplanes=8):
        """t: [N, C, H, W] non-negative ints < 2^nplanes (planes counted on the given representation)."""
        N, C, H, W = t.shape
        cp = -(-C // 8) * 8
        t = F.pad(t, (0, 0, 0, 0, 0, cp - C))
        assert (H * W) % 16 == 0
        w = t.reshape(N, cp // 8, 8, H * W // 16, 16)
        planes = torch.stack([((w >> b) & 1).amax((2, 4)) for b in range(nplanes)])   # [P, N, C/8, HW/16]: plane non-zero
        d = self.words.setdefault(name, dict(nz=torch.zeros(nplanes, dtype=torch.long), nw=0, npl=0))
        d["nz"] += planes.flatten(1).sum(1).cpu()
        d["nw"] += planes[0].numel()
        d["npl"] += int(planes.sum())

    def tensor(self, name, t):
        d = self.tens.setdefault(name, dict(max=0, zero=0, n=0))
        d["max"] = max(d["max"], int(t.abs().max()))
        d["zero"] += int((t == 0).sum())
        d["n"] += t.numel()


def forward(net, x, st):
    """Instrumented copy of IntBin.__call__ (same integer ops on IntBin's own parameters)."""
    S = net.S
    xf = data.prep(x, torch.float64)
    q = torch.round(xf / S["in"]).clamp(-127, 127).long()
    st.tensor("q", q)
    st.int8("q.tc", q & 0xFF, 8)
    st.int8("q.sm", q.abs() | ((q < 0).long() << 7), 8)
    a = net.acc(q, "stem")
    st.acc("stem", a)
    s = requant(a + net.stem_b[None, :, None, None], *net.stem_m)
    st.stream("s0", s)
    s = s.clamp(-Q16, Q16)
    for i, d in enumerate(net.blocks):
        p = f"blocks.{i}"
        if d["fp"]:
            hq = requant(s.clamp(min=0), *d["hm"], 0, 127)
            st.tensor(f"b{i}.hq", hq)
            st.int8(f"b{i}.hq", hq)
            a1 = net.acc(hq, p + ".c1")
            st.acc(p + ".c1", a1)
            z = requant(a1 + d["c1b"][None, :, None, None], *d["c1m"], 0, 127)
            st.tensor(f"b{i}.z", z)
            st.int8(f"b{i}.z", z)
            a2 = net.acc(z, p + ".c2")
            st.acc(p + ".c2", a2)
            r2 = requant(a2 + d["c2b"][None, :, None, None], *d["c2m"])
            rs = None
            if d["sc"]:
                a3 = net.acc(hq, p + ".sc")
                st.acc(p + ".sc", a3)
                rs = requant(a3 + d["scb"][None, :, None, None], *d["scm"])
        else:
            hb = (s > d["T1"][None, :, None, None]).long()
            a1 = net.acc(hb, p + ".c1")
            st.acc(p + ".c1", a1)
            z = (a1 >= d["T2"][None, :, None, None]).long()
            st.binary(f"b{i}.b1", hb)
            st.binary(f"b{i}.b2", z)
            a2 = net.acc(z, p + ".c2")
            st.acc(p + ".c2", a2)
            r2 = requant(a2, *d["c2m"]) + d["c2h"][None, :, None, None]
            rs = None
            if d["sc"]:
                a3 = net.acc(hb, p + ".sc")
                st.acc(p + ".sc", a3)
                rs = requant(a3, *d["scm"]) + d["sch"][None, :, None, None]
        if rs is None:
            rs = requant(s.clamp(min=0), *d["idm"])
        s = r2 + rs
        st.stream(f"s{i + 1}", s)
        s = s.clamp(-Q16, Q16)
    pq = requant(s.clamp(min=0).sum(dim=(2, 3)), *net.pool_m, 0, 127)
    return (igemm(F.linear, pq, net.fW8) + net.fbq).double() * net.fscale


def cdiv(a, b):
    return -torch.div(-a, b, rounding_mode="floor")


def fdiv(a, b):
    return torch.div(a, b, rounding_mode="floor")


@torch.no_grad()
def min_mult_bits(m0, sh, lo, hi, clamp=None, dev="cuda", chunk=2 ** 26):
    """Per channel c: minimal bitlen(m') s.t. requant(x, m', sh') == requant(x, m0_c, sh_c) (optionally after clamp) for all
    integers x in [lo_c, hi_c].  m0, sh, lo, hi: 1-d int64 (same length).  Returns (bits list, sh' list)."""
    out_b, out_s = [], []
    for c in range(len(m0)):
        M0, SH, LO, HI = int(m0[c]), int(sh[c]), int(lo[c]), int(hi[c])
        if M0 == 0:
            out_b.append(0), out_s.append(0)
            continue
        x = torch.arange(LO, HI + 1, device=dev, dtype=torch.int64)
        x = x[x != 0]                                                    # x = 0 -> 0 for every (m', sh')
        y = (x * M0 + (1 << (SH - 1))) >> SH
        yl, yu = y.clone(), y.clone()
        has_l = torch.ones_like(x, dtype=torch.bool)
        has_u = torch.ones_like(x, dtype=torch.bool)
        if clamp is not None:
            clo, chi = clamp
            has_u &= y < chi                                             # target clamped to chi: only y' >= chi needed
            yl = torch.where(y >= chi, torch.full_like(y, chi), yl)
            has_l &= y > clo                                             # target clamped to clo: only y' <= clo needed
            yu = torch.where(y <= clo, torch.full_like(y, clo), yu)
        best = (99, None)
        pos, neg = x > 0, x < 0
        sets = [(pos & has_l, x), (pos & has_u, x), (neg & has_l, x), (neg & has_u, x)]
        sets = [(mk, x[mk], yl[mk], yu[mk]) for mk, _ in sets]
        mval = M0 / 2 ** SH
        for s in range(0, SH + 1):
            if best[1] is not None and mval * 2 ** s > 2 ** (best[0] + 1):
                break                                                    # every feasible m' >= ~ m 2^s: more bits
            r = (1 << (s - 1)) if s > 0 else 0
            L, U = 0, 2 ** 62
            # need x m' >= yl 2^s - r (has_l) and x m' <= (yu + 1) 2^s - r - 1 (has_u)
            (_, xa, la, _), (_, xb, _, ub), (_, xc, lc, _), (_, xd, _, ud) = sets
            if xa.numel():
                L = max(L, int(cdiv(la * (1 << s) - r, xa).max()))
            if xb.numel():
                U = min(U, int(fdiv((ub + 1) * (1 << s) - r - 1, xb).min()))
            if xc.numel():
                U = min(U, int(fdiv(-(lc * (1 << s) - r), -xc).min()))
            if xd.numel():
                L = max(L, int(cdiv(-((ud + 1) * (1 << s) - r - 1), -xd).max()))
            if L <= U and bitlen(L) < best[0]:
                best = (bitlen(L), s)
        assert best[1] is not None, "original multiplier must be feasible"
        out_b.append(best[0]), out_s.append(best[1])
    return out_b, out_s


def plane_line(d, nplanes):
    nw = d["nw"]
    return " ".join(f"{1 - int(d['nz'][b]) / nw:.3f}" for b in range(nplanes)) + f"   planes/word {d['npl'] / nw:.3f}"


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--n", type=int, default=2000, help="first N val images")
    ap.add_argument("--calib", type=int, default=2000)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    dev = "cuda"
    run = os.path.basename(os.path.dirname(os.path.abspath(a.ckpt)))
    out = a.out or os.path.join(RESULTS, f"workload_{run}.txt")
    lines = []
    log = lambda s="": (print(s, flush=True), lines.append(s))

    model, ck, o, logp, fpb = build(a.ckpt, dev)
    args = ck["args"]
    signed = args["mode"] == "signed"
    fn = Folded(model, fpb, signed, args["b"])
    assert args["b"] == B
    (xt, _), (xv, yv) = data.split(dev)
    rec = {}
    for i in range(0, a.calib, 500):
        float_trace(fn, xt[i:min(i + 500, a.calib)], rec)
    net = IntBin(model, fn, rec, signed)

    st = Stats()
    xs = xv[:a.n]
    correct = 0
    for i in range(0, a.n, 500):
        xb = xs[i:i + 500]
        lg = forward(net, xb, st)
        ref = net(xb)
        assert torch.equal(lg, ref), "instrumented forward != IntBin"
        correct += int((lg.argmax(1) == yv[i:i + 500]).sum())
    log(f"{a.ckpt}: epoch {ck['epoch']}, fp_blocks {list(fpb)}; IntBin calibrated on train[:{a.calib}] (float_trace); "
        f"val[:{a.n}]; instrumented forward == IntBin logits bit-exact on all {a.n} images: PASS; "
        f"integer val[:{a.n}] acc {100 * correct / a.n:.2f} %")

    # conv geometry, input ranges
    convs = ["stem"] + [n for n in net.ic if n != "stem"]
    convs = ["stem"] + [f"blocks.{i}.{c}" for i in range(len(net.blocks)) for c in ("c1", "c2", "sc") if f"blocks.{i}.{c}" in net.ic]
    mods = dict(stem=model.stem)
    for i, blk in enumerate(model.blocks):
        for c in ("c1", "c2", "sc"):
            if getattr(blk, c) is not None:
                mods[f"blocks.{i}.{c}"] = getattr(blk, c)
    info = {}
    for n in convs:
        conv = mods[n].conv
        ic = net.ic[n]
        bi = int(n.split(".")[1]) if n != "stem" else -1
        inb = 8 if n == "stem" or bi in fpb else 1
        rng = (-127, 127) if n == "stem" else ((0, 127) if bi in fpb else (0, 1))
        W = ic.W8[:, :conv.cin].long()                                  # real channels only
        P = W.clamp(min=0).flatten(1).sum(1)
        Nn = W.clamp(max=0).flatten(1).sum(1)
        lo = P * rng[0] + Nn * rng[1]
        hi = P * rng[1] + Nn * rng[0]
        Ho, Wo = st.hw[n]
        nnz = int((W != 0).sum())
        Mfull = to_matrix(ic.W8.double(), B)
        nblk = Mfull.shape[0] * Mfull.shape[1] // B ** 2
        info[n] = dict(cin=conv.cin, cout=conv.cout, k=conv.k, s=ic.stride, Ho=Ho, Wo=Wo, inb=inb, lo=lo, hi=hi,
                       exe=nnz * Ho * Wo, slot=nblk * 16 * Ho * Wo, nblk=nblk, C=fn.fold[n]["C"],
                       bound=int(torch.maximum(lo.abs(), hi.abs()).max()), obs=int(st.accmax[n].max()))

    log("\n[1] conv workload per image  +  [2] accumulator acc' = sign(g) M x (before bias / requant)")
    log(f"{'conv':<15}{'Cin':>5}{'Cout':>5}{'k':>2}{'s':>2}{'HoxWo':>7}{'in-b':>5}{'exec MAC':>12}{'slot MAC':>12}{'fill':>7}"
        f"{'|acc| bound':>12}{'bits':>5}{'obs max':>9}{'bits':>5}")
    te = ts = 0
    for n in convs:
        d = info[n]
        te += d["exe"]
        ts += d["slot"]
        log(f"{n:<15}{d['cin']:>5}{d['cout']:>5}{d['k']:>2}{d['s']:>2}{'%dx%d' % (d['Ho'], d['Wo']):>7}{d['inb']:>5}"
            f"{d['exe']:>12}{d['slot']:>12}{d['exe'] / d['slot']:>7.3f}{d['bound']:>12}{bitlen(d['bound']) + 1:>5}"
            f"{d['obs']:>9}{bitlen(d['obs']) + 1:>5}")
    e8 = sum(info[n]["exe"] for n in convs if info[n]["inb"] == 8)
    s8 = sum(info[n]["slot"] for n in convs if info[n]["inb"] == 8)
    log(f"{'total':<15}{'':>26}{te:>12}{ts:>12}{te / ts:>7.3f}   (8-bit-input convs: exec {e8}, slot {s8}; "
        f"1-bit: exec {te - e8}, slot {ts - s8})")

    log("\n[3] int8 tensors (stem input q; fp block hq = c1/sc input, z = c1 output / c2 input); words 16 raster px x 8 ch")
    for nm in ["q"] + [f"b{i}.{t}" for i in fpb for t in ("hq", "z")]:
        d = st.tens[nm]
        log(f"  {nm:<8} max |v| {d['max']:>4}  zeros {100 * d['zero'] / d['n']:6.2f} %   elements/img {d['n'] // a.n}")
    log(f"  fraction of words with plane b all zero, b = 0..7 (LSB first):")
    for nm in ["q.tc", "q.sm"] + [f"b{i}.{t}" for i in fpb for t in ("hq", "z")]:
        lab = {"q.tc": "q (2's c)", "q.sm": "q (s-m,b7=sign)"}.get(nm, nm)
        log(f"  {lab:<16} {plane_line(st.words[nm], 8)}   words/img {st.words[nm]['nw'] // a.n}")

    log("\n[4] requant multipliers: minimal exact multiplier bits m' (any shift sh') over the worst-case domain "
        "(IntBin m0 is 31-bit)")
    log(f"  {'requant':<20}{'ch':>5}{'domain':>22}{'unclamped max/med':>20}{'clamped max/med':>18}{'sh max':>8}")
    rq = []
    rq.append(("stem_m", net.stem_m, info["stem"]["lo"] + net.stem_b, info["stem"]["hi"] + net.stem_b, None))
    for i, d in enumerate(net.blocks):
        p = f"blocks.{i}"
        if d["fp"]:
            rq.append((f"b{i}.hm", d["hm"], torch.tensor([0]), torch.tensor([Q16]), (0, 127)))
            rq.append((f"b{i}.c1m", d["c1m"], info[p + ".c1"]["lo"] + d["c1b"], info[p + ".c1"]["hi"] + d["c1b"], (0, 127)))
            rq.append((f"b{i}.c2m", d["c2m"], info[p + ".c2"]["lo"] + d["c2b"], info[p + ".c2"]["hi"] + d["c2b"], None))
            if d["sc"]:
                rq.append((f"b{i}.scm", d["scm"], info[p + ".sc"]["lo"] + d["scb"], info[p + ".sc"]["hi"] + d["scb"], None))
        else:
            rq.append((f"b{i}.c2m", d["c2m"], info[p + ".c2"]["lo"], info[p + ".c2"]["hi"], None))
            if d["sc"]:
                rq.append((f"b{i}.scm", d["scm"], info[p + ".sc"]["lo"], info[p + ".sc"]["hi"], None))
        if "idm" in d:
            rq.append((f"b{i}.idm", d["idm"], torch.tensor([0]), torch.tensor([Q16]), None))
    rq.append(("pool_m", net.pool_m, torch.tensor([0]), torch.tensor([16 * Q16]), (0, 127)))
    allbits = []
    for nm, (m0, sh), lo, hi, cl in rq:
        lo, hi = lo.cpu().long(), hi.cpu().long()
        assert len(lo) == len(m0) == len(hi)
        bu, su = min_mult_bits(m0.cpu(), sh.cpu(), lo, hi)
        allbits += bu
        cs = "-"
        if cl is not None:
            bc, _ = min_mult_bits(m0.cpu(), sh.cpu(), lo, hi, cl)
            cs = f"{max(bc)}/{statistics.median(bc):g}"
        log(f"  {nm:<20}{len(m0):>5}{'[%d, %d]' % (int(lo.min()), int(hi.max())):>22}"
            f"{'%d/%g' % (max(bu), statistics.median(bu)):>20}{cs:>18}{max(su):>8}")
    log(f"  all requants (unclamped): max {max(allbits)}, median {statistics.median(allbits):g} bits over "
        f"{len(allbits)} channel multipliers")

    log("\n[5] residual stream s_k (int16, before the saturating clamp): observed max |s_k|, saturations")
    log("  " + "  ".join(f"{k} {st.smax[k]} ({st.sat[k]})" for k in st.smax)
        + f"   total saturations {sum(st.sat.values())} over {a.n} images")

    log("\n[6] weight codes (QC coefficients of M; 8x8 blocks; sign(g) is 1 b per output channel on top)")
    log(f"  {'conv':<15}{'blocks':>8}{'0-term':>9}{'1-term':>9}{'2-term':>9}{'code bits':>11}")
    H = torch.zeros(3, dtype=torch.long)
    slot_codes, blk_codes = set(), set()
    tb = 0
    for n in convs:
        C = torch.as_tensor(info[n]["C"]).long()
        k = (C != 0).sum(-1).flatten()
        h = torch.bincount(k, minlength=3)[:3]
        assert int(h.sum()) == k.numel() == info[n]["nblk"]
        H += h
        tb += k.numel()
        nzs = torch.nonzero(C)
        for s_, v in zip(nzs[:, 2].tolist(), C[C != 0].tolist()):
            slot_codes.add((s_, v))
        flat = C.reshape(-1, B)
        for row in torch.unique(flat, dim=0).tolist():
            blk_codes.add(tuple(row))
        log(f"  {n:<15}{k.numel():>8}" + "".join(f"{int(h[j]) / k.numel():>9.3f}" for j in range(3)) + f"{10 * k.numel():>11}")
    log(f"  {'network':<15}{tb:>8}" + "".join(f"{int(H[j]) / tb:>9.3f}" for j in range(3)) + f"{10 * tb:>11}"
        f"   (counts {H.tolist()})")
    log(f"  distinct slot codes (shift, trit) used: {len(slot_codes)} of 16; distinct block codes: {len(blk_codes)} "
        f"(of 129 legal: empty + 8 shifts x 2 signs + C(8,2) x 4); code storage {10 * tb} b = {10 * tb / 8 / 1024:.1f} KiB")
    nflip = sum(int((fn.fold[n]["g"] < 0).sum()) for n in convs)
    nch = sum(info[n]["cout"] for n in convs)
    log(f"  sign(g) bits: {nch} output channels ({nflip} negative)")
    fcb = net.fW8.numel() * 8
    log(f"  FC int8 weights {tuple(net.fW8.shape)} = {fcb} b ({fcb / 8 / 1024:.1f} KiB) + int32 bias {len(net.fbq) * 32} b")

    log("\n[7] binary tensors: fraction of ones")
    for i, d in enumerate(net.blocks):
        if not d["fp"]:
            o1, o2 = st.ones[f"b{i}.b1"], st.ones[f"b{i}.b2"]
            log(f"  block {i}: b1 {o1[0] / o1[1]:.4f}   b2 {o2[0] / o2[1]:.4f}")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
