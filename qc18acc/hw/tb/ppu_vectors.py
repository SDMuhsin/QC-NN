"""PPU-lane test vectors (exact golden arithmetic of qc18acc.compile.golden.rq / Golden.conv):
python3 -m qc18acc.hw.tb.ppu_vectors OUT.hex [N]  -> one line per vector (hex fields, see tb_ppu.sv)."""
import sys

import numpy as np

from qc18acc.compile.golden import rq


def clamp(v):
    return min(max(v, 0), 127)


def main():
    out, n = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 4000
    rng = np.random.default_rng(1)
    lines = []
    for i in range(n):
        mode = i % 4
        acc = int(rng.integers(-2 ** 19, 2 ** 19)) if i % 3 else int(rng.integers(-300, 300))
        bias = int(rng.integers(-2 ** 20, 2 ** 20)) if i % 5 else int(rng.integers(-5, 5))
        d = int(rng.integers(0, 2))
        v = (-acc if d else acc) + bias
        if i % 7 == 0:                                   # tiny multipliers: exact .5 ties, negative values
            m0, sh = int(rng.integers(1, 4)), int(rng.integers(1, 4))
        else:
            m0 = int(rng.integers(1, 2 ** 31))
            target = int(rng.integers(5, 17 if mode == 1 else 11))          # |y| ~ 2^target
            sh = max(1, min(63, (abs(v) * m0).bit_length() - target))
        y = int(rq(np.int64(v), np.int64(m0), np.int64(sh)))
        if mode == 1 and not -2 ** 15 <= y < 2 ** 15:
            sh = min(63, sh + 8)
            y = int(rq(np.int64(v), np.int64(m0), np.int64(sh)))
        rlo, rhi = int(rng.integers(0, 256)), int(rng.choice([0, 255, int(rng.integers(0, 256))]))
        idm0, idsh = int(rng.integers(1, 2 ** 31)), int(rng.integers(24, 34))
        if mode == 0:
            o, oh = clamp(y), 0
        elif mode == 1:
            assert -2 ** 15 <= y < 2 ** 15
            o, oh = y & 255, (y >> 8) & 255
        elif mode == 2:
            q = rlo - 256 if rlo > 127 else rlo
            o, oh = clamp(y + int(rq(np.int64(q), np.int64(idm0), np.int64(idsh)))), 0
        else:
            R = 256 * (rhi - 256 if rhi > 127 else rhi) + rlo
            o, oh = clamp(y + R), 0
        lines.append(f"{mode:x} {acc & 0xFFFFF:05x} {bias & 0xFFFFFFFF:08x} {m0:08x} {sh:02x} {d:x} {rlo:02x} {rhi:02x} "
                     f"{idm0:08x} {idsh:02x} {o:02x} {oh:02x}\n")
    with open(out, "w") as f:
        f.writelines(lines)
    print(f"{n} PPU vectors -> {out}")


if __name__ == "__main__":
    main()
