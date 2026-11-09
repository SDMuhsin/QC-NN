"""v3 unit tests:  python3 -m qc18acc.compile3.test_compile
pair layout round trips (int8 maps incl. the odd-group stem input, int16 R byte planes), AGU on pairs (every pass /
tile / tap / pair: 8 distinct banks, the right index, address inside the 512-deep buffer), v3 kw window == direct
gather on garbage-filled buffers, weight re-pack (even / odd words == the v2 codes of groups 2j / 2j + 1), golden
GEMM == literal 4-term path on the mini program."""
import numpy as np

from qc18acc.compile import codes as K
from qc18acc.compile.layout import agu, index
from qc18acc.compile.program import RESNET18, plan

from .golden import Golden3, gather_window, lanes16
from .layout import (BANKS, DEPTH, cinp, gather_plan, join16, pairs, read_tensor, split16, tap_order, window_plan,
                     write_tensor)
from .program import from_v2, pass_codes

RNG = np.random.default_rng(0)


def test_layout():
    for C, H, lay in ((8, 32, 0), (64, 32, 1), (128, 16, 0), (512, 4, 0)):
        t = RNG.integers(-128, 128, (2, C, H, H))
        buf = RNG.integers(0, 2 ** 63, (2, BANKS * DEPTH, 2)).astype(np.uint64)
        write_tensor(buf, t, lay, 0)
        assert np.array_equal(read_tensor(buf, lay, 0, C, H, H), t)
    t = RNG.integers(-127, 128, (1, 8, 32, 32))
    buf = np.zeros((1, BANKS * DEPTH, 2), np.uint64)
    write_tensor(buf, t, 0, 0)
    # pixel (y, x) of the stem input = index y W + x: bank (y W + x) mod 8, lo half = channels 0..7
    w = lanes16(buf[0, (np.arange(1024) & 7) * DEPTH + (np.arange(1024) >> 3)])
    assert np.array_equal(w[:, :8].T.reshape(8, 32, 32), t[0]) and (w[:, 8:] == 0).all()
    R = RNG.integers(-2 ** 15, 2 ** 15, (2, 32, 4, 4))
    assert np.array_equal(join16(split16(R)), R)
    pl = split16(R)                                     # pair 2j = low bytes of groups 2j, 2j+1; 2j+1 = high bytes
    assert np.array_equal(pl[:, 0:16].astype(np.int64) & 255, R[:, 0:16] & 255) and np.array_equal(pl[:, 16:32], R[:, 0:16] >> 8)


def test_agu():
    for blocks, H in ((RESNET18, 32), ([(64, 64, 1), (64, 128, 2), (128, 128, 1)], 8)):
        P, _, T = plan(blocks, H=H)
        for p in P:
            t, q = T[p.src], pairs(p)
            npl = (t.planes + 1) // 2
            for o0 in range(0, p.Hout * p.Wout, 8):
                o = o0 + np.arange(8)
                yo, xo = o // p.Wout, o % p.Wout
                for kh, kw, j in tap_order(p.k, p.stride, p.cin8):
                    yi, xi = p.stride * yo + kh - p.pad, p.stride * xo + kw - p.pad
                    idx, val = agu(o0, kh, kw, j, q)
                    assert len(set((idx & 7).tolist())) == BANKS
                    assert np.array_equal(idx[val], index(p.in_lay, j, yi[val], xi[val], p.Hin, p.Win))
                    assert ((idx[val] >= 0) & (idx[val] < npl * t.H * t.W)).all() and (t.base + (idx[val] >> 3) < DEPTH).all()
            # window gather == direct gather (garbage outside the tensor), inputs == the map
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


def test_repack_golden():
    from qc18acc.hw.tb.mini import build
    p2 = build(np.random.default_rng(1), [(64, 64, 1), (64, 128, 2), (128, 128, 1)], 8)
    p3 = from_v2(p2, proofs=False)
    we, wo = p3.images["weights_e"], p3.images["weights_o"]
    for a, b in zip(p2.passes, p3.passes):
        c = pass_codes(p2.images["weights"], a)
        S = b.k * b.k * cinp(b.cin8)
        ce = K.word_codes(we[b.wbase:b.wbase + b.cout64 * S]).reshape(b.cout64, S, 8)
        co = K.word_codes(wo[b.wbase:b.wbase + b.cout64 * S]).reshape(b.cout64, S, 8)
        for og in range(b.cout64):
            for s, (kh, kw, j) in enumerate(tap_order(b.k, b.stride, b.cin8)):
                assert np.array_equal(ce[og, s], c[og][(kh, kw, 2 * j)])
                assert np.array_equal(co[og, s], c[og].get((kh, kw, 2 * j + 1), np.zeros(8, np.int64)))
    h2, h3 = p2.head, p3.head
    assert np.array_equal(we[h3.wbase:h3.wbase + 640], p2.images["weights"][h2.wbase:h2.wbase + 640])
    from qc18acc.compile.golden import Golden
    from qc18acc.compile.layout import write_tensor as wt2
    t = p2.tensors["img"]
    x = np.zeros((2, 8, t.H, t.W), np.int64)
    x[:, :3] = RNG.integers(-127, 128, (2, 3, t.H, t.W))
    a2 = np.zeros((2, 3, 8192), np.uint64)
    wt2(a2[:, t.buf], x, t.lay, t.base)
    a3 = np.zeros((2, 3, BANKS * DEPTH, 2), np.uint64)
    write_tensor(a3[:, t.buf], x, t.lay, t.base)
    l2 = Golden(p2.images).run(a2, snap=False)[0]
    g3 = Golden3(p3.images)
    l3 = g3.run(a3.copy(), snap=False)[0]
    l3l = g3.run(a3.copy(), snap=False, literal=True)[0]
    assert np.array_equal(l2, l3) and np.array_equal(l3, l3l)


if __name__ == "__main__":
    for t in (test_layout, test_agu, test_repack_golden):
        t()
        print("PASS", t.__name__, flush=True)
    print("ALL PASS")
