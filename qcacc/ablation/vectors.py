"""Operand streams of the array-level ablation (qcacc/ablation): the real conv1 GeMMX call of image 0.

    python3 -m qcacc.ablation.vectors OUTDIR

Writes OUTDIR/<point>.txt for the 4 points (same format for all, read by tb_abl.sv):
  dense_s2   dense core, s2 conv1 (int8 ternary weights from the QC code words, B 512 b)
  ternary    ternary core, s2 conv1 (2-bit trits, B 128 b)
  qc         QC core, s2 conv1 (QC code words, B 64 b)
  dense_base dense core, the dense baseline ResNet-8 conv1 (nn/, its own A / B / C; B 512 b)
The three s2 points get the identical A / C stream (the s2 qc-mode schedule model's conv1 call: K = 18,
N = 2, M = 128, 4608 fires); expected D = sum_k (int8(A) - int8(sub_a)) (W - sub_b) + C (int32 wrap),
cross-checked against qcacc.model.array.qc_array for the QC codes.
File: `K N M sc T`, then per output tile K x `<A 512 b hex> <B hex>`, `<C 2048 b hex>`, `<D 2048 b hex>`.
"""
import os
import sys

import numpy as np
import torch

from nn.compile.main import ref_run
from nn.compile.schedule_sim import gemmx_call, read8, run_image, temporal
from nn.compile.lower import Program
from nn.model.data import test_set
from nn.quant.quantize import IntResNet8
from qcacc.compile.lower import QCProgram
from qcacc.compile.main import S2, taps_for
from qcacc.compile.sim import qc_gemmx_call
from qcacc.hw.tb.vectors import hexv, s8
from qcacc.model.array import qc_array
from qcacc.model.codec import decode_tile

DENSE_Q = os.path.join(os.path.dirname(__file__), "..", "..", "nn", "build", "qparams.pt")


def capture(prog, img, step, qc):
    """Run image through the schedule model; return the GeMMX cfg + operands of conv `step`."""
    got = {}
    want = next(st.cfg for st in prog.steps if st.name == step)

    def call(mem, c):
        if c is want:
            K, N, M = c["K"], c["N"], c["M"]
            tl = lambda x, n: ([c[f"{x}tlbound{i}"] for i in range(n)], [c[f"{x}tlstride{i}"] for i in range(n)])
            a_addr = temporal(c["delta_local_a"], *tl("A", 6))
            b_addr = temporal(c["delta_local_b"], *tl("B", 3))
            c_addr = temporal(c["delta_local_c"], *tl("C", 3))
            A = read8(mem, a_addr, 8, c["Aslstride1"]).astype(np.int8).view(np.uint8).reshape(M * N, K, 8, 8)
            if qc:
                B = mem[b_addr[:, None] + np.arange(8)[None, :]].copy().view("<u8").reshape(M * N, K)
            else:                                            # int8 [T, K, 8 n, 8 k]
                B = read8(mem, b_addr, 8, c["Bslstride1"]).astype(np.int8).reshape(M * N, K, 8, 8)
            Cb = mem[c_addr[:, None] + np.arange(32)[None, :]].copy().view(np.int32).reshape(M * N, 1, 8)
            got.update(K=K, N=N, M=M, sa=c["subtraction_a"], sb=c["subtraction_b"], A=A, B=B,
                       C=np.broadcast_to(Cb, (M * N, 8, 8)).astype(np.int64))
        (qc_gemmx_call if qc else gemmx_call)(mem, c)

    run_image(prog, np.zeros(128 * 1024, np.uint8), img, None, call)
    return got


def expect(A, W, C, sa, sb):
    """A uint8 [T,K,8m,8k], W int [T,K,8n,8k] -> int32 [T,8m,8n]."""
    X = A.view(np.int8).astype(np.int64) - s8(sa)
    acc = np.einsum("tkmi,tkni->tmn", X, W.astype(np.int64) - s8(sb)) + C
    return (((acc + 2 ** 31) % 2 ** 32) - 2 ** 31).astype(np.int32)


def ternary_word(T):
    """T[8 n][8 k] in {-1,0,1} -> 128-bit int: trit (n, k) at bits [16 n + 2 k + 1 : 16 n + 2 k]."""
    enc = {0: 0, 1: 1, -1: 3}
    w = 0
    for n in range(8):
        for k in range(8):
            w |= enc[int(T[n, k])] << (16 * n + 2 * k)
    return w


def write(path, g, bhex, D):
    T, K = g["A"].shape[:2]
    sc = (int(g["sb"]) & 0xFF) << 8 | (int(g["sa"]) & 0xFF)
    with open(path, "w") as f:
        f.write(f"{K} {g['N']} {g['M']} {sc} {T}\n")
        for t in range(T):
            for k in range(K):
                f.write(f"{hexv(g['A'][t, k].reshape(-1))} {bhex[t][k]}\n")
            f.write(hexv(np.ascontiguousarray(g["C"][t], dtype=np.int32).view(np.uint8).reshape(-1)) + "\n")
            f.write(hexv(D[t].view(np.uint8).reshape(-1)) + "\n")
    print(f"{path}: K {K} N {g['N']} M {g['M']} fires {T * K}")


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    xt, _ = test_set()
    # --- s2, qc-mode schedule (one call per conv)
    q = torch.load(S2, weights_only=False)
    prog = QCProgram(q, "qc")
    taps, _ = taps_for(prog, IntResNet8(q), xt[[0]])
    g = capture(prog, prog.input_image(taps[0]["_input_nchw"]), "conv1", qc=True)
    T, K = g["B"].shape
    W = np.array([[decode_tile(g["B"][t, k]) for k in range(K)] for t in range(T)])   # [T,K,8n,8k]
    assert g["sb"] == 0
    D = expect(g["A"], W, g["C"], g["sa"], 0)
    Dq = qc_array(g["A"].view(np.int8).astype(np.int64) - s8(g["sa"]), g["B"]) + g["C"]
    assert np.array_equal(D, (((Dq + 2 ** 31) % 2 ** 32) - 2 ** 31).astype(np.int32)), "QC model != dense formula"
    write(f"{out}/qc.txt", g, [[f"{int(g['B'][t, k]):016x}" for k in range(K)] for t in range(T)], D)
    write(f"{out}/ternary.txt", g, [[f"{ternary_word(W[t, k]):032x}" for k in range(K)] for t in range(T)], D)
    write(f"{out}/dense_s2.txt", g, [[hexv(W[t, k].astype(np.int8).view(np.uint8).reshape(-1)) for k in range(K)]
                                     for t in range(T)], D)
    # --- dense baseline ResNet-8 (nn/), its own conv1 call
    qd = torch.load(DENSE_Q, weights_only=False)
    pd = Program(qd)
    td, _ = ref_run(IntResNet8(qd), pd, xt[[0]])
    gd = capture(pd, pd.input_image(td[0]["_input_nchw"]), "conv1", qc=False)
    Dd = expect(gd["A"], gd["B"], gd["C"], gd["sa"], gd["sb"])
    T, K = gd["B"].shape[:2]
    write(f"{out}/dense_base.txt", gd, [[hexv(gd["B"][t, k].view(np.uint8).reshape(-1)) for k in range(K)]
                                        for t in range(T)], Dd)
    nz = lambda w: float((np.asarray(w) != 0).mean())
    print(f"weight density: s2 conv1 {nz(W):.3f}, dense conv1 {nz(gd['B']):.3f}")


if __name__ == "__main__":
    main()
