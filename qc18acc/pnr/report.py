#!/usr/bin/env python3
"""Post-route power table of QC18-ACC from qc18acc/pnr/power.sh results (qc18acc/results/pnr).

    python3 qc18acc/pnr/report.py <period_ns> [pnr_tag]   (QA_V=3: the v3 design, qc18acc/results/pnr_v3/<pnr_tag>_post_*;
                                                           QA_V=4: v4, qc18acc/results/pnr_v4/)

PT (routed netlist, tt SPEF, propagated clock, flat SDF SAIF) and +dat (macro internal power replaced by the
datatable access model, as qc18acc/power/energy.py), energy per inference (159 982 cycles), clock-tree share.
"""
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "power"))
import energy  # noqa: E402

P = sys.argv[1]
PFX = f"{sys.argv[2]}_post_{P}ns" if len(sys.argv) > 2 else f"post_{P}ns"
V4 = os.environ.get("QA_V", "2") == "4"
V3 = os.environ.get("QA_V", "2") == "3" or V4                  # v4 keeps the v3 weight halves
D = Path(__file__).resolve().parent.parent / "results" / ("pnr_v4" if V4 else "pnr_v3" if V3 else "pnr")
b, dat = {}, {}
for line in (D / f"{PFX}_blocks.txt").read_text().splitlines():
    if not line.startswith("#"):
        w = line.split()
        b[w[0]] = [float(x) for x in w[1:5]] + ([int(w[6])] if len(w) > 6 else [])
for line in (D / f"{PFX}_macros.txt").read_text().splitlines():
    if line.startswith("datmacro:qa_"):
        w = line.split()
        dat[w[0].split(":", 1)[1]] = {w[i]: float(w[i + 1]) for i in range(1, len(w) - 1, 2)}
t = (D / f"{PFX}.txt").read_text()
grp = {m[0]: [float(x) for x in m[1:5]] for m in
       re.findall(r"^(clock_network|register|combinational|memory)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", t, re.M)}
tot = b["design:qa_top"]
pt = tot[3]
corr = pt + sum(dat[m]["P_dyn"] - b[f"macro:{m}"][0] for m in energy.MACRO.values())
per = float(P)
e = lambda x: x * energy.CYCLES * per * 1e-9 * 1e6
mw = lambda x: f"{x * 1e3:.2f}"
print(f"clock {P} ns ({1e3 / per:.0f} MHz), routed netlist, tt 1.0 V\n")
print("| quantity | value |")
print("|---|---|")
print(f"| PT total mW (int / switch / leak) | {mw(pt)} ({mw(tot[0])} / {mw(tot[1])} / {mw(tot[2])}) |")
print(f"| **+dat total mW** | **{mw(corr)}** |")
print(f"| **uJ / inference (+dat)** | **{e(corr):.2f}** (PT only {e(pt):.2f}) |")
print(f"| leakage share (+dat) | {100 * tot[2] / corr:.1f} % |")
c = b["cts:clock_tree_cells"]
print(f"| CTS clock-tree cells (n = {c[4]}) mW | {mw(c[3])} = {100 * c[3] / corr:.1f} % of +dat |")
if "clock_network" in grp:
    g = grp["clock_network"][3]
    print(f"| PT clock_network group (CTS buffers + ICGs + register clock pins + clock nets) mW | {mw(g)} = {100 * g / corr:.1f} % |")
print(f"| all ICGs (CKLNQD, n = {b['cg:all_icg'][4]}) mW | {mw(b['cg:all_icg'][3])} |")
print(f"| top-level glue (repair / hold buffers outside the RTL hierarchy, ties) mW | {mw(b['glue:top_leaf_cells'][3])} |")
print("\n| block | PT mW | +dat mW | leakage mW |")
print("|---|---|---|---|")
if V4:   # the two PPU units as one row
    b["hier:u_ppu"] = [x + y for x, y in zip(b["hier:g_ppu_0__u_ppu"][:4], b["hier:g_ppu_1__u_ppu"][:4])]
for k in ("u_array", "u_ppu", "u_drain", "u_head", "u_xbar", "u_agu", "u_seq", "u_host"):
    v = b[f"hier:{k}"]
    print(f"| {k} | {mw(v[3])} | {mw(v[3])} | {mw(v[2])} |")
for k, n in (("act", "activation macros"), ("wgt", "weight macros"), ("par", "param macros"), ("dsc", "descriptor macro")):
    m = energy.MACRO[k]
    v = b[f"macro:{m}"]
    print(f"| {n} | {mw(v[3])} | {mw(v[3] - v[0] + dat[m]['P_dyn'])} | {mw(v[2])} |")
if V3:   # the two weight halves as one wrapper
    b["hier:u_wmem"] = [x + y for x, y in zip(b["hier:u_wmem_e"][:4], b["hier:u_wmem_o"][:4])]
for k in ("u_act", "u_wmem", "u_pmem", "u_desc"):
    m = {"u_act": "act", "u_wmem": "wgt", "u_pmem": "par", "u_desc": "dsc"}[k]
    v, w = b[f"hier:{k}"], b[f"macro:{energy.MACRO[m]}"]
    print(f"| {k} wrapper logic | {mw(v[3] - w[3])} | {mw(v[3] - w[3])} | {mw(v[2] - w[2])} |")
print(f"| CTS clock tree | {mw(c[3])} | {mw(c[3])} | {mw(c[2])} |")
g = b["glue:top_leaf_cells"]
print(f"| top-level glue | {mw(g[3])} | {mw(g[3])} | {mw(g[2])} |")
print(f"| **total** | {mw(pt)} | {mw(corr)} | {mw(tot[2])} |")
m = re.search(r"Nets\s+(\d+)\((\S+)%\).*", t)
if m:
    print(f"\nSAIF annotation: nets from activity file {m.group(1)} ({m.group(2)} %); line: {m.group(0)[:200]}")
