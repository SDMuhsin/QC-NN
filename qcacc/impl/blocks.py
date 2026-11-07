#!/usr/bin/env python3
"""GeMMX block split of a DC report_area -hierarchy (base or QC cluster), numbers only.

    python3 -I qcacc/impl/blocks.py <run>/rpt/area.rpt

Every hierarchy's local area (comb + seq + black box) goes to the block of its deepest matching ancestor
(impl/kulcluster/summarize.py rule).  Blocks: GeMM array (tiles, row butterflies, column decoder, rest = cuts /
control), SIMD (requant table logic, lanes + cuts), CSR manager (in the QC cluster it also holds the 81 requant-table
registers), streamer, GeMMX glue, rest of the cluster (logic, RF macros).
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "impl", "kulcluster"))
from summarize import NAND2_UM2, area_rows, norm  # noqa: E402

G = r"i_snax_core_0_acc_0_snax_streamer_gemmX"
SH = G + r"/i_snax_streamer_gemmX_shell_wrapper"
BG = SH + r"/inst_block_gemm_simd"
BLOCKS = [
    ("array: tiles (64)",                  BG + r"/gemm/gemm_array/mesh/mesh_\d+_\d+"),
    ("array: row butterflies (8, QC)",     BG + r"/gemm/gemm_array/mesh/rows_\d+"),
    ("array: column decoder (QC)",         BG + r"/gemm/gemm_array/mesh/decoder"),
    ("array: rest (cuts, control)",        BG + r"/gemm"),
    ("SIMD: requant table logic (QC)",     BG + r"/simd/table_\d+"),
    ("SIMD: lanes + cuts",                 BG + r"/simd"),
    ("shell glue",                         SH),
    ("CSR manager (QC: + table regs)",     G + r"/i_snax_streamer_gemmX_csrman_wrapper"),
    ("streamer",                           G + r"/i_snax_streamer_gemmX_streamer_wrapper"),
    ("GeMMX glue",                         G),
]
BLOCKS = [(n, re.compile(r)) for n, r in BLOCKS]
REST = ("rest of cluster: logic", "rest of cluster: RF macros")


def block_of(name):
    parts = name.split("/")
    for k in range(len(parts), 0, -1):
        pre = norm("/".join(parts[:k]))
        for n, r in BLOCKS:
            if r.fullmatch(pre):
                return n
    return None


def main():
    rows = area_rows(sys.argv[1])
    top = rows[0][0]
    a = collections.OrderedDict((n, 0.0) for n, _ in BLOCKS)
    a[REST[0]] = a[REST[1]] = 0.0
    for name, tot, pct, comb, seq, bx in rows:
        b = block_of(name) if name != top else None
        if b:
            a[b] += comb + seq + bx
        else:
            a[REST[0]] += comb + seq
            a[REST[1]] += bx
    total = sum(a.values())
    gx = sum(v for k, v in a.items() if k not in REST)
    arr = sum(v for k, v in a.items() if k.startswith("array"))
    simd = sum(v for k, v in a.items() if k.startswith("SIMD"))
    print(f"# DC area by block (um2 at ss, pre-P&R), kGE = um2 / {NAND2_UM2}; % of the GeMMX accelerator")
    print(f"{'block':<34} {'um2':>10} {'kGE':>7} {'%GeMMX':>7}")
    for k, v in a.items():
        print(f"{k:<34} {v:10.0f} {v / NAND2_UM2 / 1e3:7.1f} {100 * v / gx if k not in REST else 0:7.1f}")
    for k, v in (("= GeMM array", arr), ("= SIMD (+ table logic)", simd), ("= GeMMX accelerator", gx), ("= cluster", total)):
        print(f"{k:<34} {v:10.0f} {v / NAND2_UM2 / 1e3:7.1f} {100 * v / gx:7.1f}")


if __name__ == "__main__":
    main()
