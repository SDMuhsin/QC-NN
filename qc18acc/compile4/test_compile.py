"""v4 unit tests:  python3 -m qc18acc.compile4.test_compile
16-bank layout round trips (int8 maps incl. the stem input, int16 R byte planes); AGU on 16 rows (every pass / tile /
tap / pair of ResNet-18 and an 8x8 mini net: 16 distinct banks, the right index, address inside the 256-deep
buffer); 16-slot kw window == direct gather on garbage-filled buffers; drain pixel pairs in distinct banks for
every layout / map size; v4 golden (GEMM and literal window path) == v3 golden on the mini program."""
import numpy as np

from qc18acc.compile.layout import index
from qc18acc.compile.program import RESNET18, plan

from .golden import Golden4, gather_window, lanes16
from .layout import (BANKS, DEPTH, ROWS, agu, cinp, drain_conflicts, gather_plan, join16, pairs, read_tensor, split16,
                     tap_order, window_plan, write_tensor)

RNG = np.random.default_rng(0)


def test_layout():
    for C, H, lay in ((8, 32, 0), (64, 32, 1), (128, 16, 0), (256, 8, 1), (512, 4, 0)):
        t = RNG.integers(-128, 128, (2, C, H, H))
        buf = RNG.integers(0, 2 ** 63, (2, BANKS * DEPTH, 2)).astype(np.uint64)
        write_tensor(buf, t, lay, 0)
        assert np.array_equal(read_tensor(buf, lay, 0, C, H, H), t)
    t = RNG.integers(-127, 128, (1, 8, 32, 32))
    buf = np.zeros((1, BANKS * DEPTH, 2), np.uint64)
    write_tensor(buf, t, 0, 0)
    i = np.arange(1024)                                 # pixel (y, x) = index y W + x: bank i mod 16, address i >> 4
    w = lanes16(buf[0, (i & 15) * DEPTH + (i >> 4)])
    assert np.array_equal(w[:, :8].T.reshape(8, 32, 32), t[0]) and (w[:, 8:] == 0).all()
    R = RNG.integers(-2 ** 15, 2 ** 15, (2, 32, 4, 4))
    assert np.array_equal(join16(split16(R)), R)


def test_drain_pairs():
    for H in (32, 16, 8, 4):
        for lay in (0, 1):
            assert drain_conflicts(lay, H, H, 1) == 0, (H, lay)


def test_agu():
    for blocks, H in ((RESNET18, 32), ([(64, 64, 1), (64, 128, 2), (128, 128, 1)], 8)):
        P, _, T = plan(blocks, H=H)
        for p in P:
            t, q = T[p.src], pairs(p)
            npl = (t.planes + 1) // 2
            for o0 in range(0, p.Hout * p.Wout, ROWS):
                o = o0 + np.arange(ROWS)
                yo, xo = o // p.Wout, o % p.Wout
                for kh, kw, j in tap_order(p.k, p.stride, p.cin8):
                    yi, xi = p.stride * yo + kh - p.pad, p.stride * xo + kw - p.pad
                    idx, val = agu(o0, kh, kw, j, q)
                    assert len(set((idx & 15).tolist())) == BANKS
                    assert np.array_equal(idx[val], index(p.in_lay, j, yi[val], xi[val], p.Hin, p.Win))
                    assert ((idx[val] >= 0) & (idx[val] < npl * t.H * t.W)).all() and (t.base + (idx[val] >> 4) < DEPTH).all()
            m = RNG.integers(1, 128, (8 * t.planes, t.H, t.W))
            buf = RNG.integers(0, 2 ** 63, (BANKS * DEPTH, 2)).astype(np.uint64)
            write_tensor(buf, m, t.lay, t.base)
            pos, val = gather_plan(p)
            x = lanes16(buf[pos]) * val[..., None]
            assert np.array_equal(gather_window(buf[None], p)[0], x), p.name
            mp = np.pad(m, ((0, 16 * cinp(p.cin8) - m.shape[0]), (p.pad, p.pad), (p.pad, p.pad)))
            o = np.arange(p.Hout * p.Wout)
            for s, (kh, kw, j) in enumerate(tap_order(p.k, p.stride, p.cin8)):
                ref = mp[16 * j:16 * j + 16, p.stride * (o // p.Wout) + kh, p.stride * (o % p.Wout) + kw].T
                if p.cin8 == 1:
                    ref[:, 8:] = 0
                assert np.array_equal(x[:, s], ref), (p.name, s)
            w = window_plan(p)
            assert not (w["read"] & ~w["lane"]).any()


def test_golden_vs_v3():
    from qc18acc.hw.tb.mini import build
    from qc18acc.compile3.golden import Golden3
    from qc18acc.compile3.layout import BANKS as B3, DEPTH as D3, write_tensor as wt3
    from qc18acc.compile3.program import from_v2
    from .program import check4
    p3 = from_v2(build(np.random.default_rng(1), [(64, 64, 1), (64, 128, 2), (128, 128, 1)], 8), proofs=False)
    check4(p3)
    t = p3.tensors["img"]
    x = np.zeros((2, 8, t.H, t.W), np.int64)
    x[:, :3] = RNG.integers(-127, 128, (2, 3, t.H, t.W))
    a3 = np.zeros((2, 3, B3 * D3, 2), np.uint64)
    wt3(a3[:, t.buf], x, t.lay, t.base)
    a4 = np.zeros((2, 3, BANKS * DEPTH, 2), np.uint64)
    write_tensor(a4[:, t.buf], x, t.lay, t.base)
    l3 = Golden3(p3.images).run(a3, snap=False)[0]
    g4 = Golden4(p3.images)
    l4 = g4.run(a4.copy(), snap=False)[0]
    l4l = g4.run(a4.copy(), snap=False, literal=True)[0]
    assert np.array_equal(l3, l4) and np.array_equal(l4, l4l)


if __name__ == "__main__":
    for t in (test_layout, test_drain_pairs, test_agu, test_golden_vs_v3):
        t()
        print("PASS", t.__name__, flush=True)
    print("ALL PASS")
