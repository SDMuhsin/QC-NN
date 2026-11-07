"""Unit tests of the codec and the QC array model.

    python3 -m qcacc.model.test_model [--qparams PATH]      (exit 1 on failure)

1. random QC tiles: encode/decode round trip, array model == dense GEMM (incl. int9 extremes)
2. non-QC tiles and the illegal trit 10 are rejected
3. every s2 conv: encode_conv (with row signs, conv0 padded channels as don't-care) decodes to
   sigma * W, and the array model on random activations equals the dense GEMM of the tiles
"""
import argparse
import sys

import numpy as np
import torch

from .array import qc_array
from .codec import decode_conv, decode_tile, encode_conv, encode_tile, row_signs

S2 = "/tmp/root/qc/final/int8/s2.pt"


def rand_qc_tile(rng):
    a, b = rng.integers(-1, 2, (2, 4, 4))
    T = np.zeros((8, 8), np.int64)
    T[0::2, 0::2], T[0::2, 1::2], T[1::2, 0::2], T[1::2, 1::2] = a, b, b, a
    return T


def dense(X, Tiles):
    """X [T, K, m, k], Tiles [T, K, n, k] -> [T, m, n]."""
    return np.einsum("tamk,tank->tmn", X, Tiles)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qparams", default=S2)
    a = ap.parse_args()
    rng = np.random.default_rng(0)
    fails = 0

    # 1. random tiles
    T_, K_ = 64, 16
    tiles = np.array([[rand_qc_tile(rng) for _ in range(K_)] for _ in range(T_)])
    codes = np.array([[encode_tile(t) for t in row] for row in tiles], dtype=np.uint64)
    rt = all(np.array_equal(decode_tile(c), t) for c, t in zip(codes.reshape(-1), tiles.reshape(-1, 8, 8)))
    X = rng.integers(-255, 256, (T_, K_, 8, 8))
    X[0] = 255
    X[1] = -255
    st = {}
    ok = rt and np.array_equal(qc_array(X, codes, st), dense(X, tiles))
    fails += not ok
    print(f"random tiles: {T_ * K_} tiles round trip {rt}, array == dense GEMM: {'PASS' if ok else 'FAIL'}  "
          f"(nonzero selects {st['nz_code'] / st['selects']:.1%})")

    # 2. rejection
    rej = 0
    bad = rand_qc_tile(rng)
    bad[0, 0] = -bad[1, 1] if bad[1, 1] else 1
    for f in (lambda: encode_tile(bad), lambda: encode_tile(2 * np.eye(8, dtype=np.int64)),
              lambda: decode_tile(np.uint64(0b10)), lambda: row_signs(np.eye(8, dtype=np.int64)[:, :, None, None]
                                                                       * np.array([1, -1] * 4)[:, None, None, None]
                                                                       + np.roll(np.eye(8, dtype=np.int64), 1, 1)[:, :, None, None])):
        try:
            f()
        except ValueError:
            rej += 1
    fails += rej != 4
    print(f"rejection of non-encodable tiles / illegal code: {rej}/4 {'PASS' if rej == 4 else 'FAIL'}")

    # 3. s2 layers
    q = torch.load(a.qparams, weights_only=False)
    for n, v in q["conv"].items():
        W = np.asarray(v["W"], np.int64)
        cout, cin, k, _ = W.shape
        codes, sig = encode_conv(W)
        M = decode_conv(codes)
        ok_c = np.array_equal(M[:, :cin], sig[:, None, None, None] * W)
        G, C = codes.shape[:2]
        tl = M.reshape(G, 8, C, 8, k, k).transpose(0, 2, 4, 5, 1, 3).reshape(G, -1, 8, 8)   # [g, K, n, k]
        Xs = rng.integers(-255, 256, (G, 4, tl.shape[1], 8, 8))                          # 4 tiles per group
        cs = np.broadcast_to(codes.reshape(G, 1, -1), (G, 4, tl.shape[1])).reshape(G * 4, -1)
        got = qc_array(Xs.reshape(G * 4, -1, 8, 8), cs)
        want = dense(Xs.reshape(G * 4, -1, 8, 8), np.repeat(tl, 4, axis=0))
        ok_a = np.array_equal(got, want)
        fails += not (ok_c and ok_a)
        print(f"{n}: {codes.size} tiles, {int((sig < 0).sum())} flipped rows, decode == sigma*W {ok_c}, "
              f"array == dense GEMM {ok_a}  {'PASS' if ok_c and ok_a else 'FAIL'}")
    print("TEST", "PASS" if fails == 0 else "FAIL")
    return int(fails != 0)


if __name__ == "__main__":
    sys.exit(main())
