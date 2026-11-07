"""QC-GeMMX call on a TCDM image (hook for nn.compile.schedule_sim.run_image(..., gemm=...)).

Same streamer semantics as schedule_sim.gemmx_call (A reader, broadcast C, D8 writer, RescaleSIMD);
the B reader is one 64-bit channel (one QC code word per fire), the SIMD may use the per-channel
requant table (qcacc.model.requant) and the array is
qcacc.model.array.qc_array (select activity per conv via make_gemm(..., stats)).
"""
import numpy as np

from nn.compile.schedule_sim import gemmx_call, read8, temporal
from nn.quant.hw import simd_rescale

from ..model.array import qc_array
from ..model.requant import lane_params


def qc_gemmx_call(mem, c, stats=None):
    K, N, M = c["K"], c["N"], c["M"]
    a_addr = temporal(c["delta_local_a"], [c[f"Atlbound{i}"] for i in range(6)], [c[f"Atlstride{i}"] for i in range(6)])
    b_addr = temporal(c["delta_local_b"], [c[f"Btlbound{i}"] for i in range(3)], [c[f"Btlstride{i}"] for i in range(3)])
    c_addr = temporal(c["delta_local_c"], [c[f"Ctlbound{i}"] for i in range(3)], [c[f"Ctlstride{i}"] for i in range(3)])
    d_addr = temporal(c["delta_local_d8"], [c[f"D8tlbound{i}"] for i in range(3)], [c[f"D8tlstride{i}"] for i in range(3)])
    assert len(a_addr) == len(b_addr) == M * N * K and len(c_addr) == len(d_addr) == M * N
    assert (d_addr % 64 == 0).all() and (b_addr % 8 == 0).all()
    X = read8(mem, a_addr, 8, c["Aslstride1"]).reshape(M * N, K, 8, 8) - c["subtraction_a"]
    codes = mem[b_addr[:, None] + np.arange(8)[None, :]].copy().view("<u8").reshape(M * N, K)
    cidx = c_addr[:, None] + np.arange(32)[None, :]
    Cb = mem[cidx].copy().view(np.int32).reshape(M * N, 1, 8).astype(np.int64)
    acc = qc_array(X, codes, stats) + Cb
    acc = ((acc + 2 ** 31) % 2 ** 32) - 2 ** 31
    mult, shift = lane_params(c, M * N)                  # per-lane CSRs or the per-channel table
    out = simd_rescale(acc, c["input_zp_i"], c["output_zp_i"], mult, shift, c["min_int_i"], c["max_int_i"],
                       c["double_round_i"]).astype(np.int8)
    didx = d_addr[:, None, None] + (np.arange(8) * c["D8slstride1"])[None, :, None] + np.arange(8)[None, None, :]
    mem[didx] = out.view(np.uint8)


def make_gemm(mode, prog, stats=None):
    """gemm hook for run_image: dense gemmx_call (mode gemmx) or the QC array (stats per conv)."""
    if mode == "gemmx":
        return gemmx_call
    by_cfg = {id(st.cfg): st.cfg["conv"] for st in prog.steps if st.kind == "conv"}

    def call(mem, c):
        qc_gemmx_call(mem, c, None if stats is None else stats.setdefault(by_cfg[id(c)], {}))
    return call
