"""Per-output-channel requant table of the QC-GeMMX RescaleSIMD (qcacc/hw/chisel/qcgemm/QcRequantTable.scala).

QC_RQ_MAP = enable << 31 | mod << 16 | stride; D tile t (SIMD input order) uses group
g = (t // stride) % mod (stride / mod 0 count as 1) and lane l the entry 8 g + l of the 64-entry
multiplier / shift table.  Disabled: the 8 per-lane CSR values (dense RescaleSIMD).
"""
import numpy as np

ENTRIES = 64


def lane_params(c, T):
    """call cfg c (multiplier / shift: 8 lanes; rq_map / rq_mult / rq_shift: table) ->
    (mult, shift) int64 [T, 1, 8] for the T D tiles of the call."""
    m = c.get("rq_map", 0)
    if not m >> 31:
        mult = np.broadcast_to(np.array(c["multiplier"], np.int64), (T, 1, 8))
        return mult, np.broadcast_to(np.array(c["shift"], np.int64), (T, 1, 8))
    stride, mod = max(m & 0xFFFF, 1), max((m >> 16) & 0xFF, 1)
    tm = np.zeros(ENTRIES, np.int64)
    ts = np.zeros(ENTRIES, np.int64)
    tm[:len(c["rq_mult"])] = c["rq_mult"]
    ts[:len(c["rq_shift"])] = c["rq_shift"]
    ts = ((ts & 0xFF) ^ 0x80) - 0x80                      # int8 shift fields
    g = (np.arange(T) // stride) % mod % (ENTRIES // 8)   # group register is 3 bits
    idx = g[:, None] * 8 + np.arange(8)[None, :]
    return tm[idx][:, None, :], ts[idx][:, None, :]
