"""Test vectors for the QcBlockGemm unit testbench (qcacc/hw/tb/tb_qc_blockgemm.cpp).

    python3 -m qcacc.hw.tb.vectors OUT.txt [--random N] [--real] [--seed S]

Expected D = qcacc.model.array.qc_array(X, codes) + C (int32 wrap), X = int8(A) - int8(subtraction_a),
i.e. the bit-exact M1 array model.  Cases:
  * random: random K (1..12), M*N (1..6), random legal code words (also all-zero / all-sum / all-diff
    words), int8 A, subtraction_a, random subtraction_b (ignored by QC) and int32 C (incl. wrap);
  * real (--real): every QC GeMMX call (42) of the s2 network on test image 0, captured from the
    schedule model (nn.compile.schedule_sim.run_image with qcacc's QC call): the real A tiles,
    code words and bias C of each call (C broadcast to the 8 rows, as the streamer does).
    The captured pre-SIMD accumulators are also checked against the M1 model call.
File format (hex, MSB first): `case <name> K N M subtraction_constant`, then per output tile:
K x `ab <A 512 b> <B 64 b>`, `c <2048 b>`, `d <2048 b>`; `end`.
"""
import argparse

import numpy as np

from qcacc.model.array import qc_array

TRIT = np.array([0, 1, 3], np.uint64)        # 0, +1, -1


def s8(v):
    """low byte of v as int8 (the RTL subtraction constant)."""
    return ((int(v) & 0xFF) ^ 0x80) - 0x80


def hexv(byts):
    """little-endian byte array -> MSB-first hex string."""
    return bytes(np.asarray(byts, np.uint8)[::-1]).hex()


def expect(A, codes, C, sub_a):
    """A uint8 [T, K, 8 m, 8 k], codes uint64 [T, K], C int64 [T, 8 m, 8 n] -> int32 [T, 8, 8]."""
    X = A.view(np.int8).astype(np.int64) - s8(sub_a)
    acc = qc_array(X, codes) + C
    return (((acc + 2 ** 31) % 2 ** 32) - 2 ** 31).astype(np.int32)


def write_case(f, name, A, codes, C, sub_a, sub_b, N, M):
    T, K = codes.shape
    assert T == M * N
    D = expect(A, codes, C, sub_a)
    sc = (int(sub_b) & 0xFF) << 8 | (int(sub_a) & 0xFF)
    f.write(f"case {name} {K} {N} {M} {sc}\n")
    for t in range(T):
        for k in range(K):
            f.write(f"ab {hexv(A[t, k].reshape(-1))} {int(codes[t, k]):016x}\n")
        f.write(f"c {hexv(np.ascontiguousarray(C[t], dtype=np.int32).view(np.uint8).reshape(-1))}\n")
        f.write(f"d {hexv(D[t].view(np.uint8).reshape(-1))}\n")
    return T * K


def random_codes(rng, shape, kind):
    if kind == "zero":
        return np.zeros(shape, np.uint64)
    if kind in ("sum", "diff"):              # every block a == b (sum) or a == -b (diff)
        a = rng.integers(1, 3, size=shape + (16,))
        b = a if kind == "sum" else 3 - a
        nib = TRIT[a] | TRIT[b] << np.uint64(2)
    else:
        nib = TRIT[rng.integers(0, 3, size=shape + (16,))] | TRIT[rng.integers(0, 3, size=shape + (16,))] << np.uint64(2)
    return (nib << (np.arange(16, dtype=np.uint64) * np.uint64(4))).sum(axis=-1, dtype=np.uint64)


def random_cases(f, n, rng):
    fires = 0
    kinds = ["rand"] * 6 + ["zero", "sum", "diff"]
    for i in range(n):
        K, N, M = int(rng.integers(1, 13)), int(rng.integers(1, 3)), int(rng.integers(1, 4))
        T = M * N
        A = rng.integers(0, 256, size=(T, K, 8, 8), dtype=np.uint8)
        if i % 5 == 0:                       # extremes: -128 / 127 everywhere
            A = rng.choice(np.array([0x80, 0x7F], np.uint8), size=(T, K, 8, 8))
        codes = random_codes(rng, (T, K), kinds[i % len(kinds)])
        C = rng.integers(-2 ** 31, 2 ** 31, size=(T, 8, 8), dtype=np.int64)
        if i % 4 == 1:
            C = rng.integers(-1000, 1000, size=(T, 8, 8), dtype=np.int64)
        sub_a = int(rng.integers(0, 256)) if i % 5 else int(rng.choice([0x7F, 0x80]))
        fires += write_case(f, f"rand{i}", A, codes, C, sub_a, int(rng.integers(0, 256)), N, M)
    return fires


def real_cases(f):
    """All QC calls of image 0 of the s2 network, from the schedule model."""
    import torch
    from nn.compile.schedule_sim import read8, run_image, temporal
    from nn.quant.quantize import IntResNet8
    from nn.model.data import test_set
    from qcacc.compile.lower import QCProgram
    from qcacc.compile.main import S2, taps_for
    from qcacc.compile.sim import qc_gemmx_call

    q = torch.load(S2, weights_only=False)
    prog = QCProgram(q, "qc")
    xt, _ = test_set()
    taps, _ = taps_for(prog, IntResNet8(q), xt[[0]])
    names = {id(st.cfg): st.out for st in prog.steps if st.kind == "conv"}
    fires = [0]

    def call(mem, c):
        K, N, M = c["K"], c["N"], c["M"]
        a_addr = temporal(c["delta_local_a"], [c[f"Atlbound{i}"] for i in range(6)], [c[f"Atlstride{i}"] for i in range(6)])
        b_addr = temporal(c["delta_local_b"], [c[f"Btlbound{i}"] for i in range(3)], [c[f"Btlstride{i}"] for i in range(3)])
        c_addr = temporal(c["delta_local_c"], [c[f"Ctlbound{i}"] for i in range(3)], [c[f"Ctlstride{i}"] for i in range(3)])
        A = read8(mem, a_addr, 8, c["Aslstride1"]).astype(np.int8).view(np.uint8).reshape(M * N, K, 8, 8)
        codes = mem[b_addr[:, None] + np.arange(8)[None, :]].copy().view("<u8").reshape(M * N, K)
        Cb = mem[c_addr[:, None] + np.arange(32)[None, :]].copy().view(np.int32).reshape(M * N, 1, 8)
        C = np.broadcast_to(Cb, (M * N, 8, 8)).astype(np.int64)
        # model's own X / accumulator must agree with the RTL semantics used for D
        X = read8(mem, a_addr, 8, c["Aslstride1"]).reshape(M * N, K, 8, 8) - c["subtraction_a"]
        assert np.array_equal(X, A.view(np.int8).astype(np.int64) - s8(c["subtraction_a"]))
        fires[0] += write_case(f, names[id(c)], A, codes, C, c["subtraction_a"], c["subtraction_b"], N, M)
        qc_gemmx_call(mem, c)

    mem = np.zeros(128 * 1024, np.uint8)
    run_image(prog, mem, prog.input_image(taps[0]["_input_nchw"]), None, call)
    return fires[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--random", type=int, default=200)
    ap.add_argument("--real", action="store_true")
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    with open(a.out, "w") as f:
        fr = random_cases(f, a.random, np.random.default_rng(a.seed))
        fq = real_cases(f) if a.real else 0
        f.write("end\n")
    print(f"{a.out}: {a.random} random cases ({fr} fires)" + (f", real s2 image-0 calls ({fq} fires)" if a.real else ""))


if __name__ == "__main__":
    main()
