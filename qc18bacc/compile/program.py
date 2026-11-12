"""QC18B-ACC program (qc18bacc/ARCH.md v1) from a verified qc18b E6 checkpoint:

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.program RUN/best.pt

Network / calibration: exactly qc18b.int_bin.main (build, Folded, float_trace on train[:2000] in chunks of 500 -> IntBin);
every number of the program is taken from that IntBin (the golden model), nothing is re-derived from floats.

Program = pass list (ARCH.md "Pass schedule"): stem, per binary block c1 / sc / c2, block 6 hm / c1 / sc / c2, head.
Per array pass:
  codes   8-b block code per 8x8 QC block [Cout/8, Cb] (129 legal states: empty, 8 shifts x 2 signs, C(8,2) x 4),
          decoded by DEC (256 entries, 10-b PE code {k1[2:0], t1[1:0], k2[2:0], t2[1:0]}, trit 01 = +1, 11 = -1, 00 = 0;
          -1 = illegal).  Asserted: decode(code) re-expands to qc18b's M (conv.matrix()) and sign(g) * expand(decode) ==
          the integer weights of IntBin (IntConv.W8) for every block.
  sgn     sign(g) per output channel (1 b): the PE accumulates M x, the PPU input negates (acc' = sgn acc).
  params  per output channel: stem: bias (pre-add), m', sel, T = T1 of block 0; binary c1: T2 (compare units);
          binary sc: m', sel, h = sch (r mode); binary c2: m', sel, h = c2h, idm (m', sel) of identity blocks,
          T = T1_next; block 6 (wide lanes, IntBin's 31-b m0 / sh): hm, c1 (bias, clamp [0, 127]), sc (bias, r mode),
          c2 (bias, T = T1 of block 7); head: pool m0 / sh, FC int8 + int32 bias + float dequant scale.
  m' / sel: per-channel qb_lane_s8 parameters (s' = 17 + sel, sel in [0, 8), m' < 2^29) from
          qc18bacc.workload.lane_widths(..., export) (= workload.py --lane --lane-export), cached in
          results/lane_export_<run>.txt; every row is re-checked here against IntBin (m0, sh, domain, h) and the lane
          function is checked exact (== qc18.int8.requant) on EVERY integer of the worst-case domain of every channel.
Buffers (ARCH.md "Buffers"): S (stream, 17 b x 64 x 32 x 32, in place), B1 / B2 (binary maps, 64 kb), HQ (8 planes x
  16 kb), Z (8 x 8 kb), IMG (8 planes x 8 ch x 32 x 32); every pass's source / destination is assigned and size-checked.
Worst-case bounds (interval arithmetic over the input range, real channels): PE accumulator |M x| < 2^19 (ACC_W 20
  signed), r (sc output / idm rs) within 17 b signed, every fused-lane domain inside qb_lane_s8 (x 16 b, m' 29 b,
  |y| < 2^17, registered product window 26 b, |y + h + r| < 2^18), wide lanes inside qb_lane_w (x 20 b, m 31 b, T 21 b),
  thresholds clamped to 16 b exactly (T1 vs the saturated stream, T2 vs the c1 accumulator domain).
"""
import argparse
import os
import sys
from dataclasses import dataclass, field

import numpy as np
import torch

from qc.structure import expand, to_matrix
from qc18.int8 import requant
from qc18b import data
from qc18b.int_bin import IntBin, Q16, float_trace
from qc18b.verify_bin import Folded, build
from qc18bacc import workload as wl

RESULTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "results")
B = 8                     # QC block size
KB = 36                   # bytes per chunk (9 taps x 4 groups, or 36 groups of the centre tap)
CH = 32                   # input channels per 3x3 chunk
ROWS, COLS = 16, 8        # array: 16 output pixels x 8 columns (8 output channels each)
NCH = COLS * B            # output channels per tile
ACC_W = 20
SB, NSEL, MW = 17, 8, 29  # qb_lane_s8: s' = SB + sel, sel < NSEL, m' < 2^MW, XW 16, T 16 b
XW_S, TW_S, YW = 16, 16, 18
R_W = 17                  # r (sc output, idm rs) in the stream region
XW_W, MW_W, TW_W = 20, 31, 21   # qb_lane_w
YW_W, RW_W = 19, 19       # DEVIATION: qb_lane_w y clamp 19 b (qb_lane: 18 b) and r port 19 b (block-6 sc r reaches
                          # 209 625 worst case); block-6 r is stored as two S entries (lo 16 b, hi signed)
BUFS = dict(S=(64 * 32 * 32, R_W), B1=(64 * 32 * 32, 1), B2=(64 * 32 * 32, 1), HQ=(8 * 256 * 8 * 8, 1),
            Z=(8 * 512 * 4 * 4, 1), IMG=(8 * 8 * 32 * 32, 1))    # entries, bits per entry


# ------------------------------------------------------------------------------------------------ block codes
def _states():
    st = [()]
    st += [((s, t),) for s in range(B) for t in (1, -1)]
    st += [((s1, t1), (s2, t2)) for s1 in range(B) for s2 in range(s1 + 1, B) for t1 in (1, -1) for t2 in (1, -1)]
    return st


STATES = _states()
assert len(STATES) == 129
TRIT = {0: 0, 1: 1, -1: 3}


def _tables():
    dec = np.full(256, -1, np.int64)            # 8-b code -> 10-b PE code
    key = np.full(3 ** B, -1, np.int64)         # base-3 key of the coefficient vector -> 8-b code
    for i, st in enumerate(STATES):
        terms = list(st) + [(0, 0)] * (2 - len(st))
        (k1, t1), (k2, t2) = terms
        dec[i] = (k1 << 7) | (TRIT[t1] << 5) | (k2 << 2) | TRIT[t2]
        c = np.zeros(B, np.int64)
        for s, t in st:
            c[s] = t
        key[int(((c + 1) * 3 ** np.arange(B)).sum())] = i
    return dec, key


DEC, _KEY = _tables()


def pe_coef(pe):
    """10-b PE codes (int array) -> coefficient vectors [..., 8] as the PE applies them (term (k, t): lane i += t a[(i+k)%8])."""
    pe = np.asarray(pe)
    tv = np.array([0, 1, 99, -1])                # trit 10 is illegal
    c = np.zeros(pe.shape + (B,), np.int64)
    for k, t in (((pe >> 7) & 7, tv[(pe >> 5) & 3]), ((pe >> 2) & 7, tv[pe & 3])):
        assert (t != 99).all(), "illegal trit"
        np.put_along_axis(c, k[..., None], np.take_along_axis(c, k[..., None], -1) + t[..., None], -1)
    return c


def encode(C):
    C = np.asarray(C).astype(np.int64)
    codes = _KEY[((C + 1) * 3 ** np.arange(B)).sum(-1)]
    assert (codes >= 0).all(), "block not a legal QC state"
    return codes.astype(np.uint8)


def decode(codes):
    pe = DEC[np.asarray(codes).astype(np.int64)]
    assert (pe >= 0).all(), "illegal 8-b code"
    return pe_coef(pe)


# ------------------------------------------------------------------------------------------------ lane arithmetic
def lane_s8(x, m, sel, h=0, r=0, t=None, rmode=False):
    """qb_lane_s8 (qbs_new #(16, 29, 16, 3, 17, 0)) mode 0, int64 tensors (broadcast).  Returns (y_sat or r, b)."""
    assert ((x >= -2 ** (XW_S - 1)) & (x < 2 ** (XW_S - 1))).all(), "lane x outside 16 b"
    assert (m >= 0).all() and (m < 2 ** MW).all() and (sel >= 0).all() and (sel < NSEL).all()
    p = (x * m) >> (SB - 1)                                   # registered product window
    assert (p.abs() < 2 ** 25).all(), "product window (26 b) overflow"
    q = p >> sel
    yq = q >> 1
    assert (yq.abs() < 2 ** (YW - 1)).all(), "|y| >= 2^17 (18-b truncation)"
    s = yq + h + r + (q & 1)
    assert (s.abs() < 2 ** YW).all(), "19-b sum overflow"
    if rmode:
        assert (s.abs() < 2 ** (R_W - 1)).all(), "r outside 17 b"
        return s, None
    ys = s.clamp(-Q16, Q16)
    return ys, (None if t is None else ys > t)


def lane_s8_rq(x, m, sel):
    """the same window requant as a second operand (idm rs = requant(relu(s_in))): (x m' + 2^(s'-1)) >> s'."""
    q = (x * m) >> (SB - 1 + sel)
    return (q >> 1) + (q & 1)


def lane_w(x, m0, sh, h=0, r=0, t=None, mode="sat"):
    """qb_lane_w (qb_lane #(20, 31, 21)) mode 0; mode 'u8' = output clamp [0, 127] (ARCH deviation: relu-int8 clamp),
    'r' = unsaturated 17-b r output, 'sat' = sat16(y + h + r) and b = y_sat > t."""
    assert (x.abs() < 2 ** (XW_W - 1)).all(), "wide lane x outside 20 b"
    assert (m0 >= 0).all() and (m0 < 2 ** MW_W).all() and (sh >= 1).all() and (sh < 64).all()
    assert (torch.as_tensor(r).abs() < 2 ** (RW_W - 1)).all(), "wide lane r outside 19 b"
    q = (x * m0) >> (sh - 1)
    y = ((q + 1) >> 1).clamp(-2 ** (YW_W - 1), 2 ** (YW_W - 1) - 1)
    if mode == "u8":
        return y.clamp(0, 127), None
    s = y + h + r
    if mode == "r":
        assert (s.abs() < 2 ** (RW_W - 1)).all() and (s.abs() < 2 ** (YW_W - 1) - 1).all(), "wide r outside 19 b"
        return s, None
    ys = s.clamp(-Q16, Q16)
    return ys, (None if t is None else ys > t)


# ------------------------------------------------------------------------------------------------ program
@dataclass
class Pass:
    name: str
    kind: str                 # stem | bc1 | bsc | bc2 | hm | wc1 | wsc | wc2
    block: int
    ppu: str                  # fused | compare | wide | wide-only
    src: str
    dst: list
    cin: int = 0
    cinp: int = 0
    cout: int = 0
    k: int = 0
    stride: int = 1
    pad: int = 0
    Hin: int = 0
    Win: int = 0
    Hout: int = 0
    Wout: int = 0
    inb: int = 1
    conv: str = None
    codes: np.ndarray = None  # [Cout/8, Cb] uint8
    sgn: np.ndarray = None    # [Cout] +-1
    nnz: int = 0              # nonzero weight terms (real input channels) -> executed MAC = nnz Hout Wout
    acc_bound: int = 0        # worst-case |M x|
    p: dict = field(default_factory=dict)

    @property
    def nchunk(self):
        return 1 if self.k == 1 else -(-self.cinp // CH)

    @property
    def tiles_px(self):
        return self.Hout * self.Wout // ROWS

    @property
    def tiles(self):
        return self.tiles_px * self.cout // NCH

    @property
    def mac(self):
        return self.nnz * self.Hout * self.Wout


@dataclass
class Program:
    run: str
    passes: list
    head: dict
    lut: torch.Tensor          # [3, 256] input LUT uint8 pixel -> int8 q
    buffers: dict
    checks: list


def load(ckpt, dev="cuda", calib=2000):
    """build + IntBin calibrated exactly as qc18b.int_bin.main.  Returns model, fn, net, (xv, yv)."""
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    model, ck, o, logp, fpb = build(ckpt, dev)
    args = ck["args"]
    signed = args["mode"] == "signed"
    assert args["b"] == B and signed
    fn = Folded(model, fpb, signed, args["b"])
    (xt, _), (xv, yv) = data.split(dev)
    rec = {}
    for i in range(0, calib, 500):
        float_trace(fn, xt[i:min(i + 500, calib)], rec)
    return model, fn, IntBin(model, fn, rec, signed), (xv, yv)


def _mods(model):
    mods = dict(stem=model.stem)
    for i, blk in enumerate(model.blocks):
        for c in ("c1", "c2", "sc"):
            if getattr(blk, c) is not None:
                mods[f"blocks.{i}.{c}"] = getattr(blk, c)
    return mods


def lane_export(net, info, run, ckpt):
    path = os.path.join(RESULTS, f"lane_export_{run}.txt")
    if not os.path.exists(path):
        wl.lane_widths(net, info, lambda s="": None, (path, SB, NSEL, MW))
    rows = {}
    for ln in open(path):
        f = ln.split()
        if f and f[0] == "R":
            d = rows.setdefault(f[1], dict(c=[], lo=[], hi=[], m0=[], sh=[], m=[], sel=[], h=[]))
            for k, v in zip(("c", "lo", "hi", "m0", "sh", "m", "sel", "h"), f[2:]):
                d[k].append(int(v))
    return {k: {kk: torch.tensor(vv, dtype=torch.int64) for kk, vv in v.items()} for k, v in rows.items()}, path


def _check_lane_exact(name, d, m0, sh, lo, hi, clamp16, dev):
    """qb_lane_s8 window requant == IntBin requant on every integer of [lo_c, hi_c] (stem: after the +-32767 clamp)."""
    assert torch.equal(d["m0"], m0.cpu()) and torch.equal(d["sh"], sh.cpu()), f"{name}: export m0/sh != IntBin"
    assert torch.equal(d["lo"], lo.cpu()) and torch.equal(d["hi"], hi.cpu()), f"{name}: export domain != program"
    n = 0
    for c in range(len(m0)):
        x = torch.arange(int(lo[c]), int(hi[c]) + 1, device=dev)
        ref = requant(x[None, :], m0[c:c + 1].to(dev), sh[c:c + 1].to(dev))[0]
        y, _ = lane_s8(x, d["m"][c].to(dev), d["sel"][c].to(dev))
        if not clamp16:
            y = lane_s8_rq(x, d["m"][c].to(dev), d["sel"][c].to(dev))
        ref = ref.clamp(-Q16, Q16) if clamp16 else ref
        assert torch.equal(y, ref), f"{name} ch {c}: lane != requant"
        n += x.numel()
    return n


def domain(W8, rlo, rhi):
    """acc' = W8 x for x in [rlo, rhi] per element (real input channels): per-channel (lo, hi)."""
    W = W8.long()
    P, Nn = W.clamp(min=0).flatten(1).sum(1), W.clamp(max=0).flatten(1).sum(1)
    return P * rlo + Nn * rhi, P * rhi + Nn * rlo


@torch.no_grad()
def build_program(ckpt, dev="cuda"):
    model, fn, net, val = load(ckpt, dev)
    run = os.path.basename(os.path.dirname(os.path.abspath(ckpt)))
    mods = _mods(model)
    checks = []
    fpb = fn.fpb
    assert tuple(fpb) == (6,) and len(net.blocks) == 8, "E6 network expected"

    # ---- convs: codes, sign, bounds
    conv = {}
    for n, mod in mods.items():
        cv, ic = mod.conv, net.ic[n]
        C = np.asarray(fn.fold[n]["C"])
        codes = encode(C)
        Cd = decode(codes)
        assert np.array_equal(Cd, C.astype(np.int64)), f"{n}: code round trip"
        Md = expand(torch.as_tensor(Cd, dtype=torch.float64), B)
        assert torch.equal(Md, cv.matrix().double().cpu()), f"{n}: decoded codes != qc18b M"
        sgn = torch.sign(fn.fold[n]["g"]).cpu()
        assert (sgn != 0).all()
        assert torch.equal(sgn[:, None] * Md, to_matrix(ic.W8.double().cpu(), B)), f"{n}: sign(g) decode != integer W"
        bi = -1 if n == "stem" else int(n.split(".")[1])
        rng = (-127, 127) if n == "stem" else ((0, 127) if bi in fpb else (0, 1))
        lo, hi = domain(ic.W8[:, :cv.cin], *rng)
        bound = int(torch.maximum(lo.abs(), hi.abs()).max())
        assert bound < 2 ** (ACC_W - 1), f"{n}: |acc| bound {bound} >= 2^19"
        conv[n] = dict(cin=cv.cin, cinp=ic.cp, cout=cv.cout, k=cv.k, stride=cv.stride, pad=cv.padding, codes=codes,
                       sgn=sgn.numpy().astype(np.int64), nnz=int((ic.W8[:, :cv.cin] != 0).sum()), lo=lo, hi=hi,
                       bound=bound, sgnt=sgn.long())
    checks.append(f"codes: {sum(c['codes'].size for c in conv.values())} blocks, "
                  f"{len({int(v) for c in conv.values() for v in c['codes'].ravel()})} distinct of 129 legal 8-b codes; "
                  f"decode -> qc18b M and sign(g) decode -> IntBin W8: PASS ({len(conv)} convs)")
    checks.append("PE accumulator worst case |M x| (ACC_W 20 signed, < 2^19): " +
                  " ".join(f"{n.replace('blocks.', 'b')} {c['bound']}" for n, c in conv.items()))

    # ---- lane export (qb_lane_s8 m' / sel)
    info = {n: dict(lo=c["lo"], hi=c["hi"]) for n, c in conv.items()}
    ex, expath = lane_export(net, info, run, ckpt)
    nx = _check_lane_exact("stem_m", ex["stem_m"], *net.stem_m, conv["stem"]["lo"] + net.stem_b,
                           conv["stem"]["hi"] + net.stem_b, True, dev)

    def c16(t):                                   # threshold clamp to 16 b (exactness checked by the caller)
        return t.clamp(-2 ** (TW_S - 1), 2 ** (TW_S - 1) - 1)

    passes = []
    H = 32
    d0 = net.blocks[0]
    c = conv["stem"]
    passes.append(Pass("stem", "stem", -1, "fused", "IMG", ["S", "B1"], c["cin"], c["cinp"], c["cout"], c["k"],
                       c["stride"], c["pad"], H, H, H, H, 8, "stem", c["codes"], c["sgn"], c["nnz"], c["bound"],
                       dict(bias=net.stem_b.cpu(), m=ex["stem_m"]["m"], sel=ex["stem_m"]["sel"], T=c16(d0["T1"].cpu()))))
    rbound, sbound = {}, {}
    for i, d in enumerate(net.blocks):
        p = f"blocks.{i}"
        c1, c2 = conv[p + ".c1"], conv[p + ".c2"]
        Ho = H // c1["stride"]
        geo = lambda c, Hi: (c["cin"], c["cinp"], c["cout"], c["k"], c["stride"], c["pad"], Hi, Hi, Hi // c["stride"],
                             Hi // c["stride"])
        nxt = net.blocks[i + 1] if i + 1 < len(net.blocks) else None
        T1n = None if nxt is None or nxt["fp"] else c16(nxt["T1"].cpu())
        if not d["fp"]:
            # c1: compare units, T2 vs acc' (domain must be inside 16 b for the T2 clamp to be exact)
            assert int(c1["lo"].min()) > -2 ** 15 and int(c1["hi"].max()) < 2 ** 15 - 1
            passes.append(Pass(f"b{i}.c1", "bc1", i, "compare", "B1", ["B2"], *geo(c1, H), 1, p + ".c1", c1["codes"],
                               c1["sgn"], c1["nnz"], c1["bound"], dict(T=c16(d["T2"].cpu()))))
            if d["sc"]:
                cs = conv[p + ".sc"]
                e = ex[f"b{i}.scm"]
                nx += _check_lane_exact(f"b{i}.scm", e, *d["scm"], cs["lo"], cs["hi"], False, dev)
                assert torch.equal(e["h"], d["sch"].cpu())
                y = lane_s8_rq(torch.stack([cs["lo"].cpu(), cs["hi"].cpu()]), e["m"], e["sel"]) + e["h"]
                lane_s8(torch.stack([cs["lo"].cpu(), cs["hi"].cpu()]), e["m"], e["sel"], e["h"], rmode=True)
                rbound[f"b{i}.sc"] = int(y.abs().max())
                passes.append(Pass(f"b{i}.sc", "bsc", i, "fused", "B1", ["S"], *geo(cs, H), 1, p + ".sc", cs["codes"],
                                   cs["sgn"], cs["nnz"], cs["bound"], dict(m=e["m"], sel=e["sel"], h=e["h"])))
                rlo, rhi = y.min(0).values, y.max(0).values
            else:
                e = ex[f"b{i}.idm"]
                nx += _check_lane_exact(f"b{i}.idm", e, *d["idm"], torch.tensor([0]), torch.tensor([Q16]), False, dev)
                y = lane_s8_rq(torch.tensor([0, Q16]), e["m"], e["sel"])
                rbound[f"b{i}.idm"] = int(y.abs().max())
                rlo, rhi = int(y.min()), int(y.max())
            assert max(v for k, v in rbound.items() if k.startswith(f"b{i}.")) < 2 ** (R_W - 1), "binary r outside 17 b"
            e2 = ex[f"b{i}.c2m"]
            nx += _check_lane_exact(f"b{i}.c2m", e2, *d["c2m"], c2["lo"], c2["hi"], False, dev)
            assert torch.equal(e2["h"], d["c2h"].cpu())
            xs = torch.stack([c2["lo"].cpu(), c2["hi"].cpu()])
            y2 = lane_s8_rq(xs, e2["m"], e2["sel"]) + e2["h"]
            lane_s8(xs, e2["m"], e2["sel"], e2["h"])                       # window / 18-b / 19-b asserts at the ends
            sb = int(torch.maximum((y2.max(0).values + rhi).abs(), (y2.min(0).values + rlo).abs()).max())
            assert sb < 2 ** YW, f"b{i}.c2 |y + h + r| {sb} >= 2^18"
            sbound[f"b{i}.c2"] = sb
            pr = dict(m=e2["m"], sel=e2["sel"], h=e2["h"], T=T1n, res="r" if d["sc"] else "idm")
            if not d["sc"]:
                pr.update(idm_m=ex[f"b{i}.idm"]["m"], idm_sel=ex[f"b{i}.idm"]["sel"])
            passes.append(Pass(f"b{i}.c2", "bc2", i, "fused", "B2", ["S"] + (["B1"] if T1n is not None else []),
                               *geo(c2, Ho), 1, p + ".c2", c2["codes"], c2["sgn"], c2["nnz"], c2["bound"], pr))
        else:
            # block 6 on the wide lanes (IntBin's 31-b m0 / sh)
            cs = conv[p + ".sc"]
            passes.append(Pass(f"b{i}.hm", "hm", i, "wide-only", "S", ["HQ"], cin=c1["cin"], cout=c1["cin"], Hin=H,
                               Win=H, Hout=H, Wout=H, p=dict(m0=d["hm"][0].cpu(), sh=d["hm"][1].cpu())))
            for nm, c, src, dst, kind, mk, bk in (("c1", c1, "HQ", ["Z"], "wc1", "c1m", "c1b"),
                                                  ("sc", cs, "HQ", ["S"], "wsc", "scm", "scb"),
                                                  ("c2", c2, "Z", ["S", "B1"], "wc2", "c2m", "c2b")):
                Hi = H if nm != "c2" else Ho
                m0, sh = d[mk][0].cpu(), d[mk][1].cpu()
                b = d[bk].cpu()
                xlo, xhi = c["lo"].cpu() + b, c["hi"].cpu() + b
                assert int(torch.maximum(xlo.abs(), xhi.abs()).max()) < 2 ** (XW_W - 1), f"b{i}.{nm}: x outside 20 b"
                if kind == "wsc":
                    y, _ = lane_w(torch.stack([xlo, xhi]), m0, sh, mode="r")
                    rbound[f"b{i}.sc"] = int(y.abs().max())
                pr = dict(bias=b, m0=m0, sh=sh)
                if kind == "wc2":
                    assert nxt is not None and not nxt["fp"]
                    pr["T"] = nxt["T1"].cpu()
                    assert int(pr["T"].abs().max()) < 2 ** (TW_W - 1)
                passes.append(Pass(f"b{i}.{nm}", kind, i, "wide", src, dst, *geo(c, Hi), 8, p + "." + nm, c["codes"],
                                   c["sgn"], c["nnz"], c["bound"], pr))
        H = Ho
    assert H == 4
    # wide-lane exactness of the 19-b y clamp: sat16(clamp(y) + r) == sat16(y + r) iff 2^18 - 1 >= 32767 + max |r|
    assert 2 ** (YW_W - 1) - 1 >= Q16 + rbound["b6.sc"], "wide lane y clamp not exact"
    # head: pool (wide lane, clamp [0, 127]) + FC
    assert 16 * Q16 < 2 ** (XW_W - 1)
    head = dict(pool_m0=net.pool_m[0].cpu(), pool_sh=net.pool_m[1].cpu(), fW8=net.fW8, fbq=net.fbq, fscale=net.fscale)
    checks.append(f"lane export {os.path.relpath(expath)}: qb_lane_s8 window requant == IntBin requant on every integer "
                  f"of every in-scope channel's worst-case domain ({nx} values): PASS")
    checks.append("r bounds (binary blocks 17 b signed < 65536; block 6 19 b, stored as 2 S entries): " + " ".join(f"{k} {v}" for k, v in rbound.items()))
    checks.append("c2 pass |y + h + r| (< 2^18): " + " ".join(f"{k} {v}" for k, v in sbound.items()))
    t2 = [p for p in passes if p.kind == "bc1"]
    checks.append(f"thresholds clamped to 16 b: T1 max |.| {max(int(b['T1'].abs().max()) for b in net.blocks if not b['fp'])}"
                  f", T2 max |.| {max(int(b['T2'].abs().max()) for b in net.blocks if not b['fp'])} "
                  f"(T2 clamp exact: c1 acc domains inside [-2^15, 2^15 - 1])")

    # ---- buffer assignment / size checks
    use = []
    for p in passes:
        rd = p.cin * p.Hin * p.Win * (8 if p.src in ("HQ", "Z", "IMG") else 1) if p.src != "IMG" else 8 * 8 * p.Hin * p.Win
        wr = {}
        for b in p.dst:
            wr[b] = p.cout * p.Hout * p.Wout * (8 if b in ("HQ", "Z") else 2 if (b == "S" and p.kind == "wsc") else 1)
        for b, n in [(p.src, rd)] + list(wr.items()):
            assert n <= BUFS[b][0], f"{p.name}: {b} needs {n} > {BUFS[b][0]}"
        use.append(f"{p.name} {p.src}({rd})->" + ",".join(f"{b}({n})" for b, n in wr.items()))
    checks.append("buffers (entries): " + "; ".join(use))
    # line buffer (not modelled by the dataflow, which gathers patches directly): input rows of one tile row-set +
    # the prefetch of the next, all channels, one plane; capped at the whole map
    lb = {}
    for p in passes:
        if p.k:
            tr = max(1, P_ROWS_PER_TILE(p))
            rows = min((tr - 1) * p.stride + p.k + tr * p.stride, p.Hin)
            lb[p.name] = rows * p.Win * (8 if p.src == "IMG" else p.cin)
    checks.append(f"line buffer (bits, rows x W x Cin, one plane; ARCH: max ~12 kb): max {max(lb.values())} "
                  f"({', '.join(k for k, v in lb.items() if v > 12288)} > 12 kb)")
    # in place: c2 drains read s_in / r at the addresses they write; nothing else reads S between sc and c2
    for j, p in enumerate(passes):
        if p.kind in ("bsc", "wsc"):
            nx_ = passes[j + 1]
            assert nx_.kind in ("bc2", "wc2", "wc1") and p.cout * p.Hout * p.Wout <= BUFS["S"][0]
    lut = torch.stack([torch.round(data.prep(torch.arange(256, device=dev, dtype=torch.uint8)[None, None, :, None]
                                             .expand(1, 1, 256, 3).contiguous(), torch.float64)[0, c, 0]
                                   / net.S["in"]).clamp(-127, 127).long() for c in range(3)])
    prog = Program(run, passes, head, lut, BUFS, checks)
    return prog, net, val


def P_ROWS_PER_TILE(p):
    return ROWS // p.Wout if p.Wout < ROWS else 1


def describe(prog):
    out = [f"program {prog.run}: {len(prog.passes)} passes + head"]
    out += [f"  {p.name:<7} {p.kind:<4} {p.ppu:<9} {p.src}->{'+'.join(p.dst):<6} cin {p.cin:>3} cout {p.cout:>3} k {p.k} s "
            f"{p.stride} {p.Hout:>2}x{p.Wout:<2} inb {p.inb} tiles {p.tiles if p.k else 0:>3} chunks {p.nchunk if p.k else 0:>2}"
            f" |acc|<= {p.acc_bound}" for p in prog.passes]
    out += ["  " + c for c in prog.checks]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    a = ap.parse_args()
    prog, _, _ = build_program(a.ckpt)
    print("\n".join(describe(prog)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
