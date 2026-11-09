"""Unit tests:  python3 -m qc18acc.compile.test_compile
codes (exhaustive over all 129 legal blocks and all 1024 10-b codes), wide-word fields, descriptor round-trip,
layout / AGU (every pass, tile, tap, cb: 8 distinct banks, correct index for in-range lanes, addresses inside the
tensor), AGU padding, literal block-PE == GEMM == qc.structure.expand, PPU requant == qc18.int8.requant, int16 planes."""
import numpy as np
import torch

from qc.structure import expand
from qc18.int8 import fixmul, requant

from . import codes as K
from .golden import Golden, gather_window, pe_literal, rq
from .layout import (BANKS, DEPTH, act_reads, agu, flat, gather_plan, index, join16, kw_order, mcol, split16,
                     tap_consec, tap_order, window_plan, words_to_lanes, write_tensor)
from .program import Desc, Head, encode_desc, plan

RNG = np.random.default_rng(0)


def test_codes():
    V = K.valid_blocks()
    assert len(V) == 129 and len({tuple(v) for v in V}) == 129
    c = K.encode(V)
    assert len(set(c.tolist())) == 129
    k, t = K.decode(c)
    assert np.array_equal(K.coefs(k, t), V)
    assert ((k[..., 0] <= k[..., 1]) | (t[..., 1] == 0)).all()                    # ascending shift
    legal = set()
    for code in range(1024):
        try:
            K.decode(np.array([code]))
            legal.add(code)
        except AssertionError:
            pass
    assert legal == set(c.tolist()), "exactly the 129 canonical codes decode"
    # block output formula == sum_s c[s] P_s
    for v, cc in zip(V, c):
        (k1, k2), (t1, t2) = (z[0] for z in K.decode(np.array([cc])))
        x = RNG.integers(-127, 128, 8)
        y = np.array([t1 * x[(i + k1) % 8] + t2 * x[(i + k2) % 8] for i in range(8)])
        assert np.array_equal(y, expand(torch.tensor(v[None, None], dtype=torch.float64), 8).numpy() @ x)


def test_wide():
    cds = K.encode(K.valid_blocks()[RNG.integers(0, 129, (50, 8))])
    w = K.to_wide([K.weight_word(r) for r in cds])
    assert np.array_equal(K.word_codes(w), cds) and K.from_wide(w) == [K.weight_word(r) for r in cds]
    assert all(v < 2 ** 80 for v in K.from_wide(w))
    f8 = RNG.integers(-127, 128, (20, 8))
    assert np.array_equal(K.fc_weights(K.to_wide([K.fc_word(r) for r in f8])), f8)
    P = [(-2 ** 31, 2 ** 31 - 1, 62, 1), (2 ** 31 - 1, 2 ** 30, 1, 0), (-5, 0, 1, 1), (123456, 1442937216, 32, 0)]
    w = K.to_wide([K.param_word(*p) for p in P])
    assert all(v < 2 ** 70 for v in K.from_wide(w))
    assert [tuple(int(a) for a in r) for r in zip(*K.param_fields(w))] == P


def test_desc():
    P, head, _ = plan()
    for i, p in enumerate(P):
        p.wbase, p.pbase, p.idm0, p.idsh = 1000 * i + 7, 64 * i, 2 ** 31 - 1 - i, 33
        d = Desc(encode_desc(p))
        for f in ("k", "stride", "mode", "in_lay", "out_lay", "res_lay", "in_buf", "out_buf", "res_buf", "Hin",
                  "Win", "Hout", "Wout", "cin8", "cout64", "in_base", "out_base", "res_base", "wbase", "pbase",
                  "idm0", "idsh", "pad", "last"):
            assert getattr(d, f) == getattr(p, f), f
    head.wbase, head.pbase, head.pool_m0, head.pool_sh = 21801, 4800, 1442937216, 32
    d = Desc(encode_desc(head))
    assert (d.type, d.last, d.Hin, d.Win, d.cin8, d.ncls, d.wbase, d.pbase, d.pool_m0, d.pool_sh) == \
        (2, 1, 4, 4, 64, 10, 21801, 4800, 1442937216, 32)


def test_layout_agu():
    """Every pass / tile / tap / cb: lanes hit 8 distinct banks; in-range lanes read exactly index(cb, yi, xi)
    of the input layout, at an address inside the input tensor."""
    P, _, T = plan()
    n = 0
    for p in P:
        t = T[p.src]
        for o0 in range(0, p.Hout * p.Wout, 8):
            o = o0 + np.arange(8)
            yo, xo = o // p.Wout, o % p.Wout
            for kh in range(p.k):
                for kw in range(p.k):
                    yi, xi = p.stride * yo + kh - p.pad, p.stride * xo + kw - p.pad
                    for cb in range(p.cin8):
                        idx, val = agu(o0, kh, kw, cb, p)
                        assert len(set((idx & 7).tolist())) == BANKS, "bank conflict"
                        ref = index(p.in_lay, cb, yi[val], xi[val], p.Hin, p.Win)
                        assert np.array_equal(idx[val], ref)
                        assert ((idx[val] >= 0) & (idx[val] < t.words)).all()
                        assert (t.base + (idx[val] >> 3) < DEPTH).all()
                        n += 1
    assert n > 10000


def test_agu_padding():
    P, _, T = plan()
    by = {p.name: p for p in P}
    p = by["blocks.0.c1"]                                                          # 32x32 stride 1
    assert not agu(0, 0, 1, 0, p)[1].any()                                         # top row, kh = 0
    assert agu(0, 1, 0, 0, p)[1].tolist() == [False] + [True] * 7                  # left edge
    assert agu(24, 1, 2, 0, p)[1].tolist() == [True] * 7 + [False]                 # right edge
    p = by["blocks.2.c1"]                                                          # 32x32 -> 16x16 stride 2 phase
    assert not agu(0, 0, 1, 0, p)[1].any() and agu(0, 2, 2, 0, p)[1].all()
    assert agu(16, 1, 0, 0, p)[1].tolist() == [False] + [True] * 7
    p = by["blocks.7.c1"]                                                          # 4x4: tile spans 2 rows
    assert agu(0, 1, 0, 0, p)[1].tolist() == [False, True, True, True] * 2
    assert agu(8, 2, 1, 0, p)[1].tolist() == [True] * 4 + [False] * 4
    assert by["blocks.6.sc"].pad == 0 and agu(0, 0, 0, 0, by["blocks.6.sc"])[1].all()
    # golden gather: padded lanes read zero, in-range lanes read the stored map
    for name in ("blocks.0.c1", "blocks.2.c1", "blocks.2.sc", "blocks.7.c1"):
        p, t = by[name], T[by[name].src]
        m = RNG.integers(1, 128, (8 * t.planes, t.H, t.W))
        buf = RNG.integers(0, 2 ** 63, BANKS * DEPTH).astype(np.uint64)        # garbage outside the tensor
        write_tensor(buf, m, t.lay, t.base)
        pos, val = gather_plan(p)
        x = words_to_lanes(buf[pos]) * val[..., None]
        xp = np.pad(m, ((0, 0), (p.pad, p.pad), (p.pad, p.pad)))
        o = np.arange(p.Hout * p.Wout)
        yo, xo = o // p.Wout, o % p.Wout
        for kb, (kh, kw, cb) in enumerate(tap_order(p.k, p.stride, p.cin8)):
            ref = xp[8 * cb:8 * cb + 8, p.stride * yo + kh, p.stride * xo + kw].T
            assert np.array_equal(x[:, kb], ref), (name, kh, kw, cb)
        # v2 kw window (golden literal path) == direct gather, on garbage outside the tensor
        xw = gather_window(buf[None], p)[0]
        assert np.array_equal(xw, x), name
        assert flat(np.array([9]), 3)[0] == 1 * DEPTH + 3 + 1


def test_window():
    """v2 tap order and kw window on every pass of ResNet-18 (and H = 8 mini geometry): the tap order is a
    permutation of (kh, kw, cb); the structural shift rule == the index rule (asserted in window_plan); a slot is read
    at most once per run, every valid lane is held or read, reads never exceed v1; stride-1 3x3 runs read 1 word
    per shift step except at row wraps (W = 4); stride 2: kw 0 -> 2 is a shift (same odd phase plane)."""
    from .program import RESNET18
    assert kw_order(3, 2) == [0, 2, 1] and kw_order(3, 1) == [0, 1, 2] and kw_order(1, 2) == [0]
    assert tap_consec(3, 2, 2) == [False, True, False] * 6 and tap_consec(1, 2, 3) == [False] * 3
    tot = [0, 0]
    for blocks, H in ((RESNET18, 32), ([(64, 64, 1), (64, 128, 2), (128, 128, 1)], 8)):
        P, _, _ = plan(blocks, H=H)
        for p in P:
            taps = tap_order(p.k, p.stride, p.cin8)
            assert sorted(mcol(p.k, p.cin8, *t) for t in taps) == list(range(p.K))
            w = window_plan(p)
            rd, ln = w["read"], w["lane"]
            assert not (rd & ~ln).any(), "read of a padding slot"
            v2, v1 = act_reads(p)
            assert v2 <= v1
            if p.k == 3 and p.stride == 1 and p.Wout >= 8:
                assert (rd[:, w["shift"]].sum(-1) <= 1).all(), p.name
            if H == 32:
                tot[0] += v2
                tot[1] += v1
    print(f"  ResNet-18 array act reads / image: v2 {tot[0]} vs v1 {tot[1]} ({tot[0] / tot[1]:.3f})")


def test_pe():
    """literal two-term block-PE == the golden's expanded-block GEMM == qc.structure.expand."""
    R, Kb = 16, 9
    C = K.valid_blocks()[RNG.integers(0, 129, (R, Kb))]
    cds = K.encode(C)
    x = RNG.integers(-127, 128, (2, 5, Kb, 8)).astype(np.int8)
    kk, tt = K.decode(cds)
    lit = pe_literal(x, kk, tt).reshape(2, 5, R * 8)
    M = expand(torch.tensor(C, dtype=torch.float64), 8).numpy()                   # [R*8, Kb*8]
    assert np.array_equal(lit, x.reshape(2, 5, -1).astype(np.int64) @ M.T.astype(np.int64))
    # golden pass data path (weights decoded from words)
    from .program import Pass, encode_desc
    p = Pass("t", 3, 1, 8, 8, 8, 8, 1, 1, 0)
    big = K.valid_blocks()[RNG.integers(0, 129, (8, 9))]
    words = [K.weight_word(K.encode(big)[og * 8:og * 8 + 8, mcol(3, 1, *tp)]) for og in range(1)
             for tp in tap_order(3, 1, 1)]
    h = Head(0, 0, 0, 8, 8, 1, 1)
    g = Golden(dict(weights=K.to_wide(words), params=K.to_wide([K.param_word(0, 2 ** 30, 30, 0)] * 64),
                    desc=np.array(encode_desc(p) + encode_desc(h), np.uint32)))
    (_, Wd, *_) = g._pass_data(0, g.convs[0])
    Mb = expand(torch.tensor(big, dtype=torch.float64), 8).numpy()
    perm = np.array([mcol(3, 1, *tp) for tp in tap_order(3, 1, 1)])
    assert np.array_equal(Wd.T, Mb.reshape(64, 9, 8)[:, perm].reshape(64, 72))


def test_requant():
    m0, sh = fixmul(torch.tensor(np.exp(RNG.uniform(np.log(1e-9), np.log(10), 64))))
    v = torch.tensor(RNG.integers(-2 ** 31 + 1, 2 ** 31, (100, 64)))
    assert np.array_equal(rq(v.numpy(), m0.numpy(), sh.numpy()), requant(v, m0, sh).numpy())


def test_r16():
    R = RNG.integers(-2 ** 15, 2 ** 15, (2, 16, 4, 4))
    R[0, 0, 0, :4] = [-32768, 32767, -1, 0]
    assert np.array_equal(join16(split16(R)), R)
    pl = split16(R)
    assert np.array_equal(pl[:, 0:8].astype(np.int64) & 255, R[:, 0:8] & 255) and np.array_equal(pl[:, 8:16], R[:, 0:8] >> 8)


if __name__ == "__main__":
    for t in (test_codes, test_wide, test_desc, test_layout_agu, test_agu_padding, test_window, test_pe, test_requant, test_r16):
        t()
        print("PASS", t.__name__, flush=True)
    print("ALL PASS")
