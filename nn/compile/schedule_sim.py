"""Host-side model of the compiled schedule on a 128 KiB TCDM image.

Every GeMMX call is executed from its streamer CSR values: the A/B/C readers and the D8 writer
generate their addresses exactly like the SNAX AGUs (base + sum(temporal idx * stride) +
spatial idx * spatial stride, innermost loop first), the GeMM array accumulates
C + sum (a - sa)(b - sb) over K for every (M, N) tile and the RescaleSIMD lanes requantize.
DMA copies, border fills, residual adds and pool+FC mirror nn/sw/nn_cluster.c.  The TCDM
starts with random bytes, so any read of an unwritten byte shows up as a mismatch.
"""
import numpy as np

from ..quant.hw import core_add_requant, simd_rescale
from .lower import GEMMX_OVERHEAD

# Snitch core cost model (cycles); see nn/README.md "Cycle estimate"
ADD_CYC_PER_ELEM = 22      # one core: ~19 instr/elem in add_rows (objdump) + mul/load stalls
POOL_CYC_PER_ELEM = 4
FC_CYC_PER_MAC = 6
FILL_CYC_PER_WORD = 2
SYNC_CYC = 300             # mailbox round trip core 0 <-> core 1, per job
DMA_BYTES_PER_CYC = 32     # 256-bit converted wide AXI (use_ax_bw_converter: 256)
DMA_LATENCY = 200


def temporal(base, bounds, strides):
    a = np.array([base], dtype=np.int64)
    for b, s in zip(bounds, strides):          # innermost first
        a = (np.arange(b, dtype=np.int64)[:, None] * s + a[None, :]).reshape(-1)
    return a


def read8(mem, addr, nsp, sstride):
    """addr[T] -> int8 tiles [T, nsp, 8] (nsp spatial 64-bit channels)."""
    idx = addr[:, None, None] + (np.arange(nsp) * sstride)[None, :, None] + np.arange(8)[None, None, :]
    assert idx.min() >= 0 and idx.max() < len(mem)
    return mem[idx].view(np.int8).astype(np.int64)


def gemmx_call(mem, c):
    K, N, M = c["K"], c["N"], c["M"]
    a_addr = temporal(c["delta_local_a"], [c[f"Atlbound{i}"] for i in range(6)], [c[f"Atlstride{i}"] for i in range(6)])
    b_addr = temporal(c["delta_local_b"], [c[f"Btlbound{i}"] for i in range(3)], [c[f"Btlstride{i}"] for i in range(3)])
    c_addr = temporal(c["delta_local_c"], [c[f"Ctlbound{i}"] for i in range(3)], [c[f"Ctlstride{i}"] for i in range(3)])
    d_addr = temporal(c["delta_local_d8"], [c[f"D8tlbound{i}"] for i in range(3)], [c[f"D8tlstride{i}"] for i in range(3)])
    assert len(a_addr) == len(b_addr) == M * N * K and len(c_addr) == len(d_addr) == M * N
    assert (d_addr % 64 == 0).all(), "D8 writer: tile addresses must be 64 B aligned (RTL drops bits [5:0])"
    A = read8(mem, a_addr, 8, c["Aslstride1"]).reshape(M * N, K, 8, 8) - c["subtraction_a"]
    B = read8(mem, b_addr, 8, c["Bslstride1"]).reshape(M * N, K, 8, 8) - c["subtraction_b"]
    # broadcast C: the first 256 bits (8 x int32, one per output column) of every tile
    cidx = c_addr[:, None] + np.arange(32)[None, :]
    Cb = mem[cidx].copy().view(np.int32).reshape(M * N, 1, 8).astype(np.int64)
    acc = np.einsum("tkri,tkci->trc", A, B) + Cb
    acc = ((acc + 2 ** 31) % 2 ** 32) - 2 ** 31
    mult = np.array(c["multiplier"], dtype=np.int64)
    shift = np.array(c["shift"], dtype=np.int64)
    out = simd_rescale(acc, c["input_zp_i"], c["output_zp_i"], mult, shift, c["min_int_i"], c["max_int_i"],
                       c["double_round_i"]).astype(np.int8)
    didx = d_addr[:, None, None] + (np.arange(8) * c["D8slstride1"])[None, :, None] + np.arange(8)[None, None, :]
    mem[didx] = out.view(np.uint8)


def fill_border(mem, t):
    """Mirror of nn_cluster.c fill_border: top/bottom rows, columns 0 and X0-1, the tail."""
    v = t.view(mem)
    v[:, 0], v[:, -1], v[:, :, 0], v[:, :, t.X0 - 1] = t.zp, t.zp, t.zp, t.zp
    mem[t.addr + t.C8 * t.plane:t.addr + t.size] = np.uint8(t.zp & 0xFF)


def run_image(prog, mem, img_bytes, check=None):
    """Execute all steps for one image on `mem`.  check(step, mem) is called after each step.
    Returns int32 logits."""
    T = prog.tensors
    logits = None
    for st in prog.steps:
        for b in prog.blobs:                            # DMA issued at the start of the step
            if b.issue == st.idx:
                mem[b.addr:b.addr + b.size] = np.frombuffer(b.data, np.uint8)
        if st.kind == "input":
            t = T["input"]
            mem[t.addr:t.addr + t.size] = np.frombuffer(img_bytes, np.uint8)
        elif st.kind == "conv":
            if T[st.out].border:
                fill_border(mem, T[st.out])
            gemmx_call(mem, st.cfg)
        elif st.kind == "add":
            v = st.cfg
            to = T[st.out]
            if to.border:
                fill_border(mem, to)
            a = T[st.ins[0]].interior(mem).astype(np.int64)
            b = T[st.ins[1]].interior(mem).astype(np.int64)
            o = core_add_requant(a, v["za"], v["ma"], b, v["zb"], v["mb"], v["zo"], v["lo"])
            to.interior(mem)[...] = o.astype(np.int8)
        elif st.kind == "poolfc":
            x = T["add3"].interior(mem).astype(np.int64) - st.cfg["zp_in"]   # [C8][8][8][8]
            pool = x.sum(axis=(1, 2)).reshape(-1)                            # channel c8*8+j
            fc = prog.q["fc"]
            logits = fc["W"].astype(np.int64) @ pool + fc["bias"]
        if check:
            check(st, mem)
    return logits


def cycle_estimate(prog):
    """Per-step cycle estimate (cluster clock) for one image; returns list of (name, cycles, note)."""
    rows = []
    for st in prog.steps:
        if st.kind == "input":
            t = prog.tensors["input"]
            rows.append((st.name, DMA_LATENCY + t.size // DMA_BYTES_PER_CYC, "DMA (not overlapped)"))
        elif st.kind == "conv":
            c = st.cfg
            fires = c["M"] * c["N"] * c["K"]
            busy = c["M"] * c["N"] * (c["K"] + 1)        # K fires + 1 add-C cycle per output tile
            cyc = busy + GEMMX_OVERHEAD
            to = prog.tensors[st.out]
            if to.border:
                cyc += FILL_CYC_PER_WORD * (2 * to.Wq * 2 + 4 * to.H) * to.C8
            dma = DMA_LATENCY + st.blob.size // DMA_BYTES_PER_CYC
            rows.append((st.name, cyc, f"GeMMX M={c['M']} N={c['N']} K={c['K']} fires={fires}, "
                                       f"busy-util {fires / busy:.0%}; weight DMA {dma} cyc hidden"))
        elif st.kind == "add":
            t = prog.tensors[st.out]
            n = t.C8 * 8 * t.H * t.H
            rows.append((st.name, n * ADD_CYC_PER_ELEM // 2 + SYNC_CYC, f"{n} elem on 2 cores"))
        else:
            rows.append((st.name, 4096 * POOL_CYC_PER_ELEM + 640 * FC_CYC_PER_MAC, "core 0"))
    return rows
