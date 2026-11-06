"""Bit-exact integer arithmetic of the KUL cluster, shared by the reference and the schedule model.

GeMMX (SNAX snax_cluster @ 3575d72, hw/chisel_acc/src/main/scala/snax_acc):
  * gemm/GemmTileArray.scala, Tile: per output element
        acc = C + sum_k (a_k - subtraction_a) * (b_k - subtraction_b)
    a, b, subtraction_{a,b} are int8 (9-bit difference, exact), C and acc are int32 (wraps).
  * simd/RescalePE.scala, one lane (lane = output channel % 8, CSR set per lane):
        var0 = (acc - input_zp) * multiplier             # 33b x 32b, kept in 64 bit
        var1 = int32( var0 >> (shift - 1) )              # arithmetic shift, low 32 bits
        var2 = (var1 >> 1) + output_zp        (double_round = 0, 31-bit add)
             = ((var1 +/- 1) >> 1) + output_zp (double_round = 1; +1 if var1 >= 0 else -1)
        out  = clamp(var2, min_int, max_int)  -> int8
    i.e. with double_round = 0: out = clamp(floor((acc - izp) * m / 2^shift) + ozp).
    This flow uses double_round = 0 and puts the rounding offset into the bias C
    (double_round = 1 rounds negative values asymmetrically).

Snitch cores (nn/sw, C on rv32im): residual add + requant
        t   = (a - za) * ma + (b - zb) * mb + 2^(s-1)    # int32, cannot overflow (checked)
        out = clamp((t >> s) + zo, lo, 127)

All functions accept numpy int arrays or torch integer tensors (int64).
"""
import numpy as np
import torch


def _wrap(v, bits):
    """Two's-complement wrap of an int64 array/tensor to `bits` bits (int64 ops already wrap
    modulo 2^64, which is exactly the 64-bit truncation of the 65-bit Chisel product)."""
    if bits == 64:
        return v
    m = 1 << bits
    return ((v + (m >> 1)) % m) - (m >> 1)


def simd_rescale(acc, input_zp, output_zp, multiplier, shift, min_int, max_int, double_round=0):
    """RescalePE on int64 acc (already wrapped to int32).  Per-lane params may be arrays
    broadcastable against acc (channel axis)."""
    lib = torch if isinstance(acc, torch.Tensor) else np
    var0 = _wrap((acc - input_zp) * multiplier, 64)
    var1 = _wrap(var0 >> (shift - 1), 32)
    if double_round:
        var1 = lib.where(var1 >= 0, var1 + 1, var1 - 1)
        var1 = _wrap(var1, 32)
    var2 = _wrap((var1 >> 1) + output_zp, 31)
    return lib.clip(var2, min_int, max_int) if lib is np else torch.clamp(var2, min_int, max_int)


ADD_SHIFT = 16       # fixed-point shift of the residual-add requant on the cores


def core_add_requant(a, za, ma, b, zb, mb, zo, lo):
    """Residual add on the Snitch cores (see nn/sw/nn_cluster.c, add_requant)."""
    lib = torch if isinstance(a, torch.Tensor) else np
    t = (a - za) * ma + (b - zb) * mb + (1 << (ADD_SHIFT - 1))
    out = (t >> ADD_SHIFT) + zo
    return lib.clip(out, lo, 127) if lib is np else torch.clamp(out, lo, 127)


def quantize_multiplier(real, bits=31):
    """real > 0 -> (m, s) with m in [2^(bits-1), 2^bits) and real ~= m / 2^s, 1 <= s <= 63."""
    real = float(real)
    assert real > 0
    s = int(np.floor(np.log2((2 ** bits - 1) / real)))
    m = int(round(real * 2.0 ** s))
    if m >= 2 ** bits:
        m //= 2
        s -= 1
    assert 1 <= s <= 63 and 0 < m < 2 ** 31, (real, m, s)
    return m, s
