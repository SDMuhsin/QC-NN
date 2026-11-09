"""Compiler: IntNet (qc18/int8.py) -> pass list, buffer / layout / base assignment, memory images
(weight SRAM, param SRAM, descriptor RAM), and the per-layer bound proofs (ARCH.md + Appendix).

Pass order: stem; per block c1, [sc (RAW16)], c2 (RES_ID / RES_R); then the head.  Buffers rotate as in ARCH.md:
X / Y / Z = the block input / c1 output / (identity: block output, conv-sc: R planes), starting X = A, Y = B,
Z = C; an identity block's output is Z (next X = Z), a conv-sc block writes its output back into X.
"""
from dataclasses import dataclass, field as dfield

import numpy as np
import torch

from qc.structure import decompose, expand, to_matrix
from qc18.verify import fold

from . import codes as K
from .layout import BANKS, DEPTH, PHASE, RASTER, mcol, tap_order

RELU, RAW16, RES_ID, RES_R = range(4)
MODES = ("RELU", "RAW16", "RES_ID", "RES_R")
BUFS = "ABC"
T_CONV, T_HEAD = 1, 2
DESC_WORDS = 8
ACC_BITS = 20                                   # PE accumulator (signed)
RESNET18 = [(64, 64, 1), (64, 64, 1), (64, 128, 2), (128, 128, 1), (128, 256, 2), (256, 256, 1),
            (256, 512, 2), (512, 512, 1)]


@dataclass
class Tensor:
    name: str
    C: int
    H: int
    W: int
    buf: int
    r16: bool = False
    lay: int = RASTER
    base: int = 0

    @property
    def planes(self):
        return (2 if self.r16 else 1) * self.C // 8

    @property
    def words(self):
        return self.planes * self.H * self.W


@dataclass
class Pass:
    name: str
    k: int
    stride: int
    Hin: int
    Win: int
    Hout: int
    Wout: int
    cin8: int
    cout64: int
    mode: int
    src: str = ""
    dst: str = ""
    res: str = ""
    in_buf: int = 0
    in_lay: int = 0
    in_base: int = 0
    out_buf: int = 0
    out_lay: int = 0
    out_base: int = 0
    res_buf: int = 0
    res_lay: int = 0
    res_base: int = 0
    wbase: int = 0
    pbase: int = 0
    idm0: int = 0
    idsh: int = 0
    last: int = 0
    proof: dict = dfield(default_factory=dict)

    @property
    def pad(self):
        return self.k // 2

    @property
    def K(self):
        return self.k * self.k * self.cin8


@dataclass
class Head:
    in_buf: int
    in_lay: int
    in_base: int
    Hin: int
    Win: int
    cin8: int
    ncls: int
    wbase: int = 0
    pbase: int = 0
    pool_m0: int = 0
    pool_sh: int = 1
    src: str = ""


# ---- pass schedule, buffers, layouts -------------------------------------------------------------------------
def plan(blocks=RESNET18, H=32, stem_cout=64):
    """-> (passes, head, tensors).  Geometry, buffers, layouts, bases; no weights."""
    A, B_, C = 0, 1, 2
    T = {"img": Tensor("img", 8, H, H, C), "stem": Tensor("stem", stem_cout, H, H, A)}
    P = [Pass("stem", 3, 1, H, H, H, H, 1, stem_cout // 64, RELU, "img", "stem")]
    x, xb = "stem", A
    for i, (cin, cout, s) in enumerate(blocks):
        n, Ho = f"blocks.{i}", H // s
        yb, zb = (xb + 1) % 3, (xb + 2) % 3
        T[n + ".c1"] = Tensor(n + ".c1", cout, Ho, Ho, yb)
        P.append(Pass(n + ".c1", 3, s, H, H, Ho, Ho, cin // 8, cout // 64, RELU, x, n + ".c1"))
        if s != 1 or cin != cout:
            T[n + ".sc"] = Tensor(n + ".sc", cout, Ho, Ho, zb, r16=True)
            P.append(Pass(n + ".sc", 1, s, H, H, Ho, Ho, cin // 8, cout // 64, RAW16, x, n + ".sc"))
            T[n + ".c2"] = Tensor(n + ".c2", cout, Ho, Ho, xb)
            P.append(Pass(n + ".c2", 3, 1, Ho, Ho, Ho, Ho, cout // 8, cout // 64, RES_R, n + ".c1", n + ".c2",
                          n + ".sc"))
        else:
            T[n + ".c2"] = Tensor(n + ".c2", cout, Ho, Ho, zb)
            P.append(Pass(n + ".c2", 3, 1, Ho, Ho, Ho, Ho, cout // 8, cout // 64, RES_ID, n + ".c1", n + ".c2", x))
            xb = zb
        x, H = n + ".c2", Ho
    head = Head(T[x].buf, RASTER, 0, H, H, T[x].C // 8, 10, src=x)
    # layout of each tensor from the stride of its array consumers
    for t in T.values():
        st = {p.stride for p in P if p.src == t.name}
        assert len(st) <= 1, f"{t.name}: array consumers with different strides"
        t.lay = PHASE if st == {2} else RASTER
    head.in_lay = T[x].lay
    assert head.in_lay == RASTER
    for p in P:
        s, d = T[p.src], T[p.dst]
        p.in_buf, p.in_lay, p.in_base = s.buf, s.lay, s.base
        p.out_buf, p.out_lay, p.out_base = d.buf, d.lay, d.base
        if p.res:
            r = T[p.res]
            p.res_buf, p.res_lay, p.res_base = r.buf, r.lay, r.base
    check_buffers(P, T, head)
    return P, head, T


def check_buffers(P, T, head):
    """Every tensor fits its buffer (8 banks x 1024 words) and no pass overwrites a live tensor."""
    for t in T.values():
        assert t.words % BANKS == 0 and t.base + t.words // BANKS <= DEPTH, f"{t.name} does not fit"
    prod = {"img": -1, **{p.dst: i for i, p in enumerate(P)}}
    last = {n: max([i for i, p in enumerate(P) if n in (p.src, p.res)] + [len(P) if n == head.src else -1])
            for n in T}
    for j, p in enumerate(P):
        assert p.out_buf not in ((p.in_buf, p.res_buf) if p.res else (p.in_buf,)), f"{p.name}: buffer clash"
        for n, t in T.items():
            if n != p.dst and t.buf == p.out_buf and prod[n] < j <= last[n]:
                lo, hi = T[p.dst].base, T[p.dst].base + T[p.dst].words // BANKS
                assert hi <= t.base or lo >= t.base + t.words // BANKS, f"{p.name} overwrites live {n}"


# ---- descriptors ---------------------------------------------------------------------------------------------
def encode_desc(p):
    """Pass or Head -> 8 x 32-b words (Appendix)."""
    head = isinstance(p, Head)
    w = [0] * DESC_WORDS
    if head:
        w[0] = T_HEAD | (p.in_lay << 8) | (p.in_buf << 11) | (1 << 17)
        w[1] = p.Hin | (p.Win << 8)
        w[2] = p.cin8 | (p.ncls << 16)
        w[3] = p.in_base
        w[4], w[5], w[6], w[7] = p.wbase, p.pbase, p.pool_m0, p.pool_sh
    else:
        w[0] = (T_CONV | (p.k << 2) | (p.stride << 4) | (p.mode << 6) | (p.in_lay << 8) | (p.out_lay << 9)
                | (p.res_lay << 10) | (p.in_buf << 11) | (p.out_buf << 13) | (p.res_buf << 15) | (p.last << 17))
        w[1] = p.Hin | (p.Win << 8) | (p.Hout << 16) | (p.Wout << 24)
        w[2] = p.cin8 | (p.cout64 << 16)
        w[3] = p.in_base | (p.out_base << 10) | (p.res_base << 20)
        w[4], w[5], w[6], w[7] = p.wbase, p.pbase, p.idm0, p.idsh
    lim = (1 << 2, 0, 0, 1 << 30, 1 << 20, 1 << 16, 1 << 31, 1 << 6)
    assert all(0 <= v < 2 ** 32 for v in w) and all(l == 0 or w[i] < l for i, l in enumerate(lim) if i)
    return w


class Desc:
    """Decoded descriptor (field names as Pass / Head)."""

    def __init__(self, w):
        w = [int(v) for v in w]
        f = lambda v, pos, n: (v >> pos) & ((1 << n) - 1)
        self.type, self.last = f(w[0], 0, 2), f(w[0], 17, 1)
        self.k, self.stride, self.mode = f(w[0], 2, 2), f(w[0], 4, 2), f(w[0], 6, 2)
        self.in_lay, self.out_lay, self.res_lay = f(w[0], 8, 1), f(w[0], 9, 1), f(w[0], 10, 1)
        self.in_buf, self.out_buf, self.res_buf = f(w[0], 11, 2), f(w[0], 13, 2), f(w[0], 15, 2)
        self.Hin, self.Win, self.Hout, self.Wout = (f(w[1], s, 8) for s in (0, 8, 16, 24))
        self.cin8, self.cout64 = f(w[2], 0, 16), f(w[2], 16, 16)
        self.in_base, self.out_base, self.res_base = f(w[3], 0, 10), f(w[3], 10, 10), f(w[3], 20, 10)
        self.wbase, self.pbase = w[4], w[5]
        if self.type == T_HEAD:
            self.ncls, self.pool_m0, self.pool_sh = self.cout64, w[6], w[7]
        else:
            self.idm0, self.idsh = w[6], w[7]
        self.pad = self.k // 2


def read_program(desc):
    """Descriptor RAM words -> [Desc] up to and including the one with `last` (the head)."""
    out = []
    for i in range(0, len(desc), DESC_WORDS):
        d = Desc(desc[i:i + DESC_WORDS])
        out.append(d)
        if d.last:
            return out
    raise ValueError("no last descriptor")


# ---- weights, params, proofs ---------------------------------------------------------------------------------
def mults(net, name):
    if name == "stem":
        return net.stem_m
    i, c = name.split(".")[1:]
    return net.blocks[int(i)][c + "m"]


def blocks_of(net):
    return [(e["c1"].W8.shape[1], e["c1"].W8.shape[0], e["c1"].stride if isinstance(e["c1"].stride, int) else e["c1"].stride[0]) for e in net.blocks]


def rq(v, m0, sh):
    return (v * m0 + (1 << (sh - 1))) >> sh


def prove(p, C, prm):
    """Worst case over all inputs in range: |partial acc| < 2^19, |d acc + bias| < 2^31, RAW16 |R| < 2^15."""
    M = expand(torch.as_tensor(C, dtype=torch.float64), 8).numpy().astype(np.int64)    # from the codes
    lane = np.arange(M.shape[1]) % 8
    hi = np.full(M.shape[1], 127)
    lo = np.where(p.name == "stem", np.where(lane < 3, -127, 0), 0)
    hi = np.where((p.name == "stem") & (lane >= 3), 0, hi)
    amax = np.maximum(M * hi, M * lo).sum(1)
    amin = np.minimum(M * hi, M * lo).sum(1)
    absb = (np.abs(M) * np.maximum(np.abs(lo), np.abs(hi))).sum(1)
    bias, m0, sh, d = prm
    vlo = np.where(d == 1, -amax, amin) + bias
    vhi = np.where(d == 1, -amin, amax) + bias
    pr = dict(acc=int(absb.max()), v=int(max(np.abs(vlo).max(), np.abs(vhi).max())))
    assert pr["acc"] < 2 ** (ACC_BITS - 1), f"{p.name}: accumulator bound {pr['acc']}"
    assert pr["v"] < 2 ** 31, f"{p.name}: |acc + bias| bound {pr['v']}"
    ylo = [rq(int(a), int(m), int(s)) for a, m, s in zip(vlo, m0, sh)]
    yhi = [rq(int(a), int(m), int(s)) for a, m, s in zip(vhi, m0, sh)]
    pr["y"] = max(max(map(abs, ylo)), max(map(abs, yhi)))
    if p.mode == RAW16:
        assert pr["y"] < 2 ** 15, f"{p.name}: |R| bound {pr['y']}"
    pr["acc_bits"] = int(pr["acc"]).bit_length() + 1                   # signed
    return pr


def weight_words(p, cds):
    """Codes [64 cout64, K] (column blocks of M in (kh, kw, cb) order) -> 80-b words of the pass in array order:
    og outer, then the tap order of layout.tap_order (kh, cb, kw; stride-2 3x3: kw 0, 2, 1)."""
    cols = [mcol(p.k, p.cin8, kh, kw, cb) for kh, kw, cb in tap_order(p.k, p.stride, p.cin8)]
    return [K.weight_word(cds[og * 8:(og + 1) * 8, kb]) for og in range(p.cout64) for kb in cols]


class Program:
    def __init__(self, passes, head, tensors, weights, params, desc):
        self.passes, self.head, self.tensors = passes, head, tensors
        self.images = dict(weights=weights, params=params, desc=desc)

    def sizes(self):
        nw, npm, nd = len(self.images["weights"]), len(self.images["params"]), len(self.images["desc"])
        return dict(weight_words=nw, weight_bytes=nw * K.WEIGHT_BITS // 8, param_words=npm,
                    param_bytes=npm * K.PARAM_BITS // 8, desc_words=nd, desc_bytes=4 * nd,
                    act_bytes=3 * BANKS * DEPTH * 8)


def build(net, model):
    """IntNet + its float model (for sign(s_c) per channel) -> Program."""
    P, head, T = plan(blocks_of(net), stem_cout=net.stem.W8.shape[0])
    sign = {n: torch.sign(fold(cb.bn)[0].double()).cpu() for n, cb in model.convbns()}
    conv = {n: cb.conv for n, cb in model.convbns()}
    ww, pw = [], []
    for p in P:
        L, d = net.layers[p.name], sign[p.name]
        M = to_matrix(L.W8.double().cpu() * d[:, None, None, None], 8)              # QC matrix of d_c M
        assert torch.equal(M, conv[p.name].matrix().double().cpu())
        assert M.shape == (64 * p.cout64, 8 * p.K)
        cds = K.encode(decompose(M, 8, signed=True))                                # [R, Kb]
        kk, tt = K.decode(cds)
        C = K.coefs(kk, tt)
        p.wbase = len(ww)
        ww += weight_words(p, cds)
        m0, sh = (t.cpu().numpy().astype(np.int64) for t in mults(net, p.name))
        bias = L.bq.cpu().numpy().astype(np.int64)
        dd = (d.numpy() < 0).astype(np.int64)
        p.pbase = len(pw)
        pw += [K.param_word(*v) for v in zip(bias, m0, sh, dd)]
        if p.mode == RES_ID:
            m, s = net.blocks[int(p.name.split(".")[1])]["idm"]
            p.idm0, p.idsh = int(m[0]), int(s[0])
        p.proof = prove(p, C, (bias, m0, sh, dd))
    # head: FC words after the conv weights (cb outer, class j inner), FC biases after the conv params
    W8 = net.fW8.cpu().numpy().astype(np.int64)                                     # [10, 512]
    head.ncls = W8.shape[0]
    head.wbase = len(ww)
    for cb in range(head.cin8):
        for j in range(head.ncls):
            ww.append(K.fc_word(W8[j, 8 * cb:8 * cb + 8]))
    head.pbase = len(pw)
    fb = net.fbq.cpu().numpy().astype(np.int64)
    assert np.abs(fb).max() + 8 * head.cin8 * 127 * 127 < 2 ** 31, "FC accumulator bound"
    pw += [K.param_word(int(b), 0, 0, 0) for b in fb]
    head.pool_m0, head.pool_sh = int(net.pool_m[0][0]), int(net.pool_m[1][0])
    assert 16 * 127 * head.pool_m0 < 2 ** 62
    desc = [w for p in P for w in encode_desc(p)] + encode_desc(head)
    return Program(P, head, T, K.to_wide(ww), K.to_wide(pw), np.array(desc, dtype=np.uint32))
