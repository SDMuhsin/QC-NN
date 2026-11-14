#!/usr/bin/env python3
"""Per-hierarchy area of the qb_chip DC run (rpt/area.rpt, report_area -hierarchy -nosplit) -> R4 table (um2).
    area_summary.py <area.rpt>
logic = cell area without the macros (black boxes) of the subtree; macros listed by type from rpt/macro_cells.rpt
when given as a 2nd argument."""
import re
import sys
from collections import defaultdict

rows = {}
for line in open(sys.argv[1]):
    w = line.split()
    if len(w) == 7 and re.match(r"^[\d.]+$", w[1]) and re.match(r"^[\d.]+$", w[3]):
        rows[w[0]] = dict(tot=float(w[1]), comb=float(w[3]), seq=float(w[4]), bb=float(w[5]), d=w[6])
top = [k for k in rows if "/" not in k and rows[k]["tot"] == max(r["tot"] for r in rows.values())][0]


def sub(pfx_re):
    """sum of (tot, bb) over the top-most rows matching pfx_re (full-name regex, relative to the top)"""
    sel = [k for k in rows if re.search(pfx_re, k)]
    sel = [k for k in sel if not any(k != j and k.startswith(j + "/") for j in sel)]
    tot = sum(rows[k]["tot"] for k in sel)
    bb = sum(rows[j]["bb"] for j in rows for k in sel if j == k or j.startswith(k + "/"))
    return tot, bb, len(sel)


cats = [("core: PE array (16x8 PEs)", r"^u_top/u_core/[^/]*u_pe$"),
        ("core: fused lanes (256)", r"^u_top/u_core/[^/]*u_lf$"),
        ("core: wide lanes (32)", r"^u_top/u_core/[^/]*u_lw$"),
        ("core: lane param banks", r"^u_top/u_core/[^/]*(u_pbf|u_pbw)$"),
        ("core: decoders + BR", r"^u_top/u_core/[^/]*(u_br|u_dec)$"),
        ("core: total", r"^u_top/u_core$"),
        ("act supply (qb_act2)", r"^u_top/u_act$"),
        ("sequencer (qb_seq)", r"^u_top/[^/]*u_seq$"),
        ("params path (qb_prm)", r"^u_top/[^/]*u_prm$"),
        ("head (qb_head)", r"^u_head$"),
        ("u_top macro wrappers", r"^u_top/g_(wl|s|map|img)_[^/]*u_m$"),
        ("u_top total", r"^u_top$")]
res = {}
for name, r in cats:
    t, b, n = sub(r)
    res[name] = (t - b, b, n)
core = res["core: total"][0]
res["core: other (port regs, cmp, ctl)"] = (core - sum(res[k][0] for k in res if k.startswith("core:") and k != "core: total"), 0, 0)
ut = res["u_top total"][0]
res["top glue in qb_top (write-back, delay lines, dist)"] = (ut - core - sum(res[k][0] for k in ("act supply (qb_act2)", "sequencer (qb_seq)", "params path (qb_prm)", "u_top macro wrappers")), 0, 0)
chip = rows[top]["tot"]; chip_bb = sum(r["bb"] for r in rows.values())
res["qb_chip glue (host port, head cfg)"] = (chip - chip_bb - ut - res["head (qb_head)"][0], 0, 0)
print(f"# {sys.argv[1]}: top {top}, total cell area {chip:.0f} um2, macros {chip_bb:.0f}, logic {chip - chip_bb:.0f}")
order = ["core: PE array (16x8 PEs)", "core: fused lanes (256)", "core: wide lanes (32)", "core: lane param banks",
         "core: decoders + BR", "core: other (port regs, cmp, ctl)", "core: total", "act supply (qb_act2)",
         "sequencer (qb_seq)", "params path (qb_prm)", "head (qb_head)", "u_top macro wrappers",
         "top glue in qb_top (write-back, delay lines, dist)", "qb_chip glue (host port, head cfg)"]
for k in order:
    lg, bb, n = res[k]
    print(f"{k:55s} logic_um2 {lg:12.0f} mm2 {lg / 1e6:.3f}" + (f"  (n {n})" if n > 1 else ""))
print(f"{'logic total':55s} logic_um2 {chip - chip_bb:12.0f} mm2 {(chip - chip_bb) / 1e6:.3f}")
if len(sys.argv) > 2:
    mt = defaultdict(lambda: [0, 0.0])
    for line in open(sys.argv[2]):
        w = line.split()
        if len(w) >= 3:
            mt[w[1]][0] += 1; mt[w[1]][1] += float(w[2])
    for k, (n, a) in sorted(mt.items()):
        print(f"macro {k:20s} n {n:3d} um2 {a:10.0f} mm2 {a / 1e6:.3f}")
    print(f"macro total n {sum(v[0] for v in mt.values())} mm2 {sum(v[1] for v in mt.values()) / 1e6:.3f}")
print(f"chip total (logic + macros) mm2 {chip / 1e6:.3f}")
