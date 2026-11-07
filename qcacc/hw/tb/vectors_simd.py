"""Test vectors for the RescaleSIMD + per-channel requant table testbench (tb_qc_simd.cpp).

    python3 -m qcacc.hw.tb.vectors_simd OUT.txt [--random N] [--real] [--seed S]

Expected int8 D = nn.quant.hw.simd_rescale with the per-tile lane parameters of
qcacc.model.requant.lane_params (table: group (t / stride) % mod, or the 8 per-lane CSRs when the
table is disabled).  Cases:
  * random: T tiles (1..40), table enabled (3/4 of the cases) with N = mod 1..8 groups and stride 1..3,
    random 64-entry multiplier / shift table, zero points, clamps, double rounding, int32 inputs;
  * real (--real): the 9 one-call-per-conv QC GeMMX calls of s2 image 0 (schedule model): their
    pre-SIMD accumulators, CSRs and requant table (qcacc.compile.lower.rq_table).
File format (hex, MSB first): `case <name> T`, `ctrl` + 13 words (dense SIMD CSRs 0..12), `rq <map>
<mult 2048 b> <shift 512 b>`, then T x (`in <2048 b>`, `out <512 b>`); `end`.
"""
import argparse

import numpy as np

from nn.quant.hw import simd_rescale
from qcacc.hw.tb.vectors import hexv
from qcacc.model.requant import ENTRIES, lane_params


def u8(x):
    return int(x) & 0xFF


def write_case(f, name, acc, c):
    """acc int64 [T, 8, 8] (int32 range), c: SIMD fields + rq_map / rq_mult / rq_shift."""
    T = acc.shape[0]
    mult, shift = lane_params(c, T)
    out = simd_rescale(acc, c["input_zp_i"], c["output_zp_i"], mult, shift, c["min_int_i"], c["max_int_i"],
                       c["double_round_i"]).astype(np.int8)
    sh, m = c["shift"], c["multiplier"]
    ctrl = [(u8(c["min_int_i"]) << 24) | (u8(c["max_int_i"]) << 16) | (u8(c["output_zp_i"]) << 8) | u8(c["input_zp_i"]),
            int(c["double_round_i"]),
            sum(u8(sh[i]) << (8 * i) for i in range(4)), sum(u8(sh[4 + i]) << (8 * i) for i in range(4))] + \
           [int(x) & 0xFFFFFFFF for x in m] + [T]
    tm = np.zeros(ENTRIES, np.int64)
    ts = np.zeros(ENTRIES, np.int64)
    tm[:len(c["rq_mult"])] = c["rq_mult"]
    ts[:len(c["rq_shift"])] = c["rq_shift"]
    f.write(f"case {name} {T}\nctrl {' '.join(f'{w:08x}' for w in ctrl)}\n")
    f.write(f"rq {c['rq_map']:08x} {hexv(tm.astype(np.int32).view(np.uint8))} "
            f"{hexv((ts & 0xFF).astype(np.uint8))}\n")
    for t in range(T):
        f.write(f"in {hexv(np.ascontiguousarray(acc[t], np.int32).view(np.uint8).reshape(-1))}\n")
        f.write(f"out {hexv(out[t].view(np.uint8).reshape(-1))}\n")
    return T


def random_cases(f, n, rng):
    tiles = 0
    for i in range(n):
        T = int(rng.integers(1, 41))
        en = i % 4 != 3
        mod, stride = int(rng.integers(1, 9)), int(rng.integers(1, 4))
        real_like = i % 2 == 0
        if real_like:   # s2-like: |m| in [2^30, 2^31), shift 30..45, moderate accumulators
            tm = rng.integers(2 ** 30, 2 ** 31, ENTRIES) * rng.choice([-1, 1], ENTRIES)
            ts = rng.integers(30, 46, ENTRIES)
            acc = rng.integers(-2 ** 18, 2 ** 18, (T, 8, 8))
        else:
            tm = rng.integers(-2 ** 31, 2 ** 31, ENTRIES)
            ts = rng.integers(1, 64, ENTRIES)
            acc = rng.integers(-2 ** 31, 2 ** 31, (T, 8, 8))
        lo, hi = sorted(int(x) for x in rng.integers(-128, 128, 2))
        c = dict(input_zp_i=int(rng.integers(-128, 128)), output_zp_i=int(rng.integers(-128, 128)),
                 min_int_i=lo, max_int_i=hi, double_round_i=int(rng.integers(0, 2)),
                 shift=[int(x) for x in ts[:8][::-1]], multiplier=[int(x) for x in tm[:8][::-1]],
                 rq_map=((1 << 31) if en else 0) | (mod << 16) | stride,
                 rq_mult=[int(x) for x in tm], rq_shift=[int(x) for x in ts])
        tiles += write_case(f, f"rand{i}", acc, c)
    return tiles


def real_cases(f):
    import torch
    import qcacc.compile.sim as sim
    from nn.compile.schedule_sim import run_image
    from nn.quant.quantize import IntResNet8
    from nn.model.data import test_set
    from qcacc.compile.lower import QCProgram
    from qcacc.compile.main import S2, taps_for

    q = torch.load(S2, weights_only=False)
    prog = QCProgram(q, "qc")
    assert not prog.per_group
    xt, _ = test_set()
    taps, _ = taps_for(prog, IntResNet8(q), xt[[0]])
    names = {id(st.cfg): st.out for st in prog.steps if st.kind == "conv"}
    cur, tiles = {}, [0]
    orig_lp, orig_sr = sim.lane_params, sim.simd_rescale

    def lp(c, T):
        cur["c"] = c
        return orig_lp(c, T)

    def sr(acc, *args):
        tiles[0] += write_case(f, names[id(cur["c"])], np.asarray(acc, np.int64), cur["c"])
        return orig_sr(acc, *args)

    sim.lane_params, sim.simd_rescale = lp, sr
    try:
        mem = np.zeros(128 * 1024, np.uint8)
        run_image(prog, mem, prog.input_image(taps[0]["_input_nchw"]), None, sim.make_gemm("qc", prog))
    finally:
        sim.lane_params, sim.simd_rescale = orig_lp, orig_sr
    return tiles[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--random", type=int, default=200)
    ap.add_argument("--real", action="store_true")
    ap.add_argument("--seed", type=int, default=2)
    a = ap.parse_args()
    with open(a.out, "w") as f:
        tr = random_cases(f, a.random, np.random.default_rng(a.seed))
        tq = real_cases(f) if a.real else 0
        f.write("end\n")
    print(f"{a.out}: {a.random} random SIMD cases ({tr} tiles)" + (f", 9 real s2 calls ({tq} tiles)" if a.real else ""))


if __name__ == "__main__":
    main()
