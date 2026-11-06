#!/usr/bin/env python3
"""TCDM dump of a gate-level run -> the 32 x 512 x 64 bit bank format of the RTL dumps (nn/sim/tcdm_check.py).

    tcdm_macro.py <run dir>      reads <run dir>/out/macro_<k>.mem, writes <run dir>/out/tcdm_<k>.hex

In the netlist each TCDM bank is one ARM RF macro kul_rf_512x64m4 (column mux 4).  Its behavioural
model stores `reg [255:0] mem [0:127]`: word A sits in row A >> 2, and bit b of the word is bit
4 * b + (A & 3) of that row (model write/read: data spread 1-of-4 and shifted by the mux address).
The rows are dumped in binary (a hex digit would mix 4 words, so one never-written word would hide its
neighbours); a byte with an X/Z bit is written as "xx" (tcdm_check.py counts it as X).
"""
import sys
from pathlib import Path

ROWS, MUX, BITS, NB = 128, 4, 64, 32


def convert(src, dst):
    rows = {}
    for line in Path(src).read_text().splitlines():
        line = line.strip()
        if line.startswith("@"):
            r, v = line[1:].split()
            rows[int(r, 16)] = v.lower()
    assert len(rows) == ROWS, f"{src}: {len(rows)} rows"
    out = []
    for a in range(ROWS * MUX):
        v = rows[a >> 2]
        bits = []                                     # bit b of word a, '?' if unknown
        for b in range(BITS):
            ch = v[len(v) - 1 - (MUX * b + (a & 3))]  # bit position in the 256-bit row
            bits.append(ch if ch in "01" else "?")
        word = ""
        for byte in range(BITS // 8 - 1, -1, -1):
            bb = bits[8 * byte:8 * byte + 8]
            word += "xx" if "?" in bb else f"{int(''.join(reversed(bb)), 2):02x}"
        out.append(f"@{a:x} {word}\n")
    Path(dst).write_text("".join(out))


if __name__ == "__main__":
    d = Path(sys.argv[1]) / "out"
    for k in range(NB):
        convert(d / f"macro_{k}.mem", d / f"tcdm_{k}.hex")
