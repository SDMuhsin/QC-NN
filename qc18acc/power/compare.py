#!/usr/bin/env python3
"""v1 vs v2 tables of QC18-ACC (results/power_v2.md):
    python3 qc18acc/power/compare.py [mode=sdf] [period=2.5] > tables.md
Power: results/power (v1, netlist qa_w3.3) and results/power_v2 (v2, qa2_w3.3), the energy.py loader (+dat = macro
internal power from the datatable model); area / fmax: impl/results/<tag>/{area,timing}.txt; PE-internal breakdown:
results/power_v2/<mode>_<p>ns_pe.txt (pe_power.tcl)."""
import re
import sys
from pathlib import Path

from energy import ADDS, CYCLES, MACRO, MACS, blocks, load, summary
import energy

Q = Path(__file__).resolve().parent.parent
mode = sys.argv[1] if len(sys.argv) > 1 else "sdf"
per = sys.argv[2] if len(sys.argv) > 2 else "2.5"
VER = (("v1", "power", "qa_w3.3", 946644), ("v2", "power_v2", "qa2_w3.3", 409572))   # array act-bank reads / image


def run(sub):
    energy.R = Q / "results" / sub
    return load(mode, per)


def impl(tag):
    a = (Q / "impl" / "results" / tag / "area.txt").read_text()
    t = (Q / "impl" / "results" / tag / "timing.txt").read_text()
    g = lambda pat, s=a: float(re.search(pat, s, re.M).group(1))
    f = {c: g(rf"^{c} clock qa_clk .* fmax_mhz (\S+)", t) for c in ("ss", "tt", "ff")}
    return dict(total=g(r"total_mm2 (\S+)"), logic=g(r"logic_mm2 (\S+)"), kge=g(r"logic_kGE (\S+)"),
                pe=g(r"one PE .* = (\S+) kGE"), arr=float(re.search(r"^pe_array.*\s(\S+)\s+\S+\s*$", a, re.M).group(1)), **f)


rs = {v: run(sub) for v, sub, _, _ in VER}
im = {v: impl(tag) for v, _, tag, _ in VER}
ard = {v: n for v, _, _, n in VER}
mw = lambda x: f"{x * 1e3:.1f}"
t = CYCLES * float(per) * 1e-9
print(f"| quantity ({mode} SAIF, {per} ns = {1e3 / float(per):.0f} MHz, tt, +dat) | v1 | v2 | v2 - v1 |")
print("|---|---|---|---|")
row = lambda n, a, b, f=mw, d=True: print(f"| {n} | {f(a)} | {f(b)} | {(f(b - a) if d else '')} |")
tot = {v: summary(r) for v, r in rs.items()}
row("total power mW (+dat)", tot["v1"][1], tot["v2"][1])
row("total power mW (PT only)", tot["v1"][0], tot["v2"][0])
row("energy uJ / inference (+dat)", tot["v1"][1] * t * 1e3, tot["v2"][1] * t * 1e3)
row("pJ / dense-equivalent MAC", tot["v1"][1] * t / MACS * 1e9, tot["v2"][1] * t / MACS * 1e9, lambda x: f"{x * 1e3:.4f}")
bl = {v: {n: c for n, _, c, _ in blocks(r)} for v, r in rs.items()}
for n in bl["v1"]:
    row(f"&nbsp;&nbsp;{n} mW", bl["v1"][n], bl["v2"][n])
icg = rs["v2"]["b"].get("macro_icg", [0, 0, 0, 0])[3]
row("&nbsp;&nbsp;of which macro clock gates (33 CKLNQD, in the wrapper logic rows) mW", 0.0, icg)
row("leakage mW", tot["v1"][2], tot["v2"][2])
for k, lab in (("act", "act"), ("wgt", "weight"), ("par", "param"), ("dsc", "desc")):
    a, b = rs["v1"]["dat"][MACRO[k]], rs["v2"]["dat"][MACRO[k]]
    row(f"{lab} macros: reads / cycle (all instances)", a["reads_pc"], b["reads_pc"], lambda x: f"{x:.3f}")
    row(f"{lab} macros: clock edges / cycle per instance", a["clk_per_cycle"], b["clk_per_cycle"], lambda x: f"{x:.3f}")
des = {v: sum(d["P_desel"] for d in r["dat"].values()) for v, r in rs.items()}
row("macro deselected-clock power mW (all macros)", des["v1"], des["v2"])
rd = {v: rs[v]["dat"][MACRO["act"]]["P_read"] for v in rs}
row("act macro read power mW", rd["v1"], rd["v2"])
row("array act-bank reads / image (RTL counter; v1 = model)", ard["v1"], ard["v2"], lambda x: f"{x:.0f}")
row("array act-bank reads / cycle", ard["v1"] / CYCLES, ard["v2"] / CYCLES, lambda x: f"{x:.3f}")
for k, lab, f in (("total", "area mm2 (total)", "{:.3f}"), ("logic", "logic mm2", "{:.3f}"), ("kge", "logic kGE", "{:.1f}"),
                  ("arr", "PE array kGE", "{:.1f}"), ("pe", "one PE kGE", "{:.2f}"), ("ss", "fmax ss MHz", "{:.1f}"),
                  ("tt", "fmax tt MHz", "{:.1f}"), ("ff", "fmax ff MHz", "{:.1f}")):
    row(lab, im["v1"][k], im["v2"][k], lambda x, f=f: f.format(x))
pe = Q / "results" / "power_v2" / f"{mode}_{per}ns_pe.txt"
if pe.exists():
    txt = pe.read_text()
    G = {m[0]: [float(x) for x in m[1:]] for m in re.findall(r"^pe:(\w+) (\S+) (\S+) (\S+) (\S+)$", txt, re.M)}
    s = sum(v[3] for v in G.values())
    chk = re.search(r"pe:sum_groups (\S+) pe:hier_total (\S+) array_total (\S+)", txt)
    names = dict(rot="rotators (u_rot1 + u_rot2, mux cells)", tadd="trit / negate + 2-term adders (u_tadd)",
                 accadd="accumulator adders (u_acc)", accreg="accumulator registers (160 b, data part)",
                 shreg="shadow registers (160 b, data part)", top="PE top-level logic: shadow capture / shift-in (drain) muxes", clock="clock: DC clock gates + register clock pins")
    print(f"\nPE-internal breakdown, v2 {mode} SAIF {per} ns, per PE averaged over 64 PEs (sum of groups "
          f"{float(chk[1]) * 1e6:.1f} uW = PE hierarchy {float(chk[2]) * 1e6:.1f} uW; PE array {float(chk[3]) * 1e3:.2f} mW):\n")
    print("| group | internal uW | switching uW | leakage uW | total uW | % of PE | x64 mW |")
    print("|---|---|---|---|---|---|---|")
    for g, v in G.items():
        print(f"| {names.get(g, g)} | {v[0] * 1e6:.1f} | {v[1] * 1e6:.1f} | {v[2] * 1e6:.2f} | {v[3] * 1e6:.1f} | "
              f"{100 * v[3] / s:.1f} | {64 * v[3] * 1e3:.2f} |")
