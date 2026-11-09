#!/usr/bin/env python3
"""v2 vs v3 (Kb = 2) tables of QC18-ACC (results/v3.md):
    python3 qc18acc/power/compare3.py [mode=sdf] [period=2.5] > tables.md
Power: results/power_v2 (netlist qa2_w3.3) and results/power_v3 (qa3_w3.3), the energy.py loader (+dat = macro
internal power from the datatable model); area / fmax: impl/results/<tag>/{area,timing}.txt; PE-internal groups:
results/power_v{2,3}/<mode>_<p>ns_pe.txt (pe_power.tcl; v3 u_acc = fused trits + 4-term + accumulate, tadd empty).
Energy per image = P x cycles x period (START..DONE, RTL = GLS); per block = / 8 724 480 QC blocks per image (the
v3 stem's odd zero blocks are not counted).  Predictions: ARCH.md "v3"."""
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import energy  # noqa: E402

Q = Path(__file__).resolve().parent.parent
mode = sys.argv[1] if len(sys.argv) > 1 else "sdf"
per = sys.argv[2] if len(sys.argv) > 2 else "2.5"
BLOCKS = 8724480
VER = {"v2": ("power_v2", "qa2_w3.3", 159982, 136320, "qa_act_1024x64m8"),
       "v3": ("power_v3", "qa3_w3.3", 81438, 68736, "qa_act_512x64m4")}
GROUPS = dict(rot="rotators (v2 2, v3 4 x 8-lane)", tadd="trits + 2-term adders (v2 u_tadd; v3: in u_acc)",
              accadd="accumulate adders (v2 u_acc 20-b add; v3 u_acc fused trits + 4 terms + acc)",
              accreg="accumulator registers (data part)", shreg="shadow registers (data part)",
              top="PE top level: shadow capture / shift-in muxes", clock="clock: DC clock gates + register clock pins")


def run(v):
    sub, _, cyc, _, act = VER[v]
    energy.R = Q / "results" / sub
    energy.CYCLES = cyc
    energy.V3 = v == "v3"
    energy.MACRO["act"] = act
    r = energy.load(mode, per)
    return r, energy.summary(r), {n: c for n, _, c, _ in energy.blocks(r)}


def impl(tag):
    a = (Q / "impl" / "results" / tag / "area.txt").read_text()
    t = (Q / "impl" / "results" / tag / "timing.txt").read_text()
    g = lambda pat, s=a: float(re.search(pat, s, re.M).group(1))
    f = {c: g(rf"^{c} clock qa_clk .* fmax_mhz (\S+)", t) for c in ("ss", "tt", "ff")}
    return dict(total=g(r"total_mm2 (\S+)"), macro=g(r"macro_mm2 (\S+)"), logic=g(r"logic_mm2 (\S+)"),
                kge=g(r"logic_kGE (\S+)"), pe=g(r"one PE .* = (\S+) kGE"),
                arr=float(re.search(r"^pe_array.*\s(\S+)\s+\S+\s*$", a, re.M).group(1)),
                ppu=float(re.search(r"^ppu.*\s(\S+)\s+\S+\s*$", a, re.M).group(1)), **f)


def pe_groups(v):
    p = Q / "results" / VER[v][0] / f"{mode}_{per}ns_pe.txt"
    if not p.exists():
        return None
    return {m[0]: float(m[4]) for m in re.findall(r"^pe:(\w+) (\S+) (\S+) (\S+) (\S+)$", p.read_text(), re.M)}


def main():
    R = {v: run(v) for v in VER}
    I = {v: impl(VER[v][1]) for v in VER}
    T = {v: VER[v][2] * float(per) * 1e-9 for v in VER}
    print(f"| quantity ({mode} SAIF, {per} ns = {1e3 / float(per):.0f} MHz, tt, +dat) | v2 | v3 | v3 / v2 |")
    print("|---|---|---|---|")

    def row(n, a, b, f="{:.1f}"):
        print(f"| {n} | {f.format(a)} | {f.format(b)} | {b / a if a else float('nan'):.3f} |")
    row("cycles / image (START..DONE, measured)", VER["v2"][2], VER["v3"][2], "{:.0f}")
    row("array busy cycles / image", VER["v2"][3], VER["v3"][3], "{:.0f}")
    row("total power mW (+dat)", R["v2"][1][1] * 1e3, R["v3"][1][1] * 1e3)
    row("total power mW (PT only)", R["v2"][1][0] * 1e3, R["v3"][1][0] * 1e3)
    E = {v: R[v][1][1] * T[v] * 1e6 for v in VER}
    row("energy uJ / inference (+dat)", E["v2"], E["v3"], "{:.2f}")
    row("leakage mW", R["v2"][1][2] * 1e3, R["v3"][1][2] * 1e3, "{:.2f}")
    row("leakage energy uJ / inference", R["v2"][1][2] * T["v2"] * 1e6, R["v3"][1][2] * T["v3"] * 1e6, "{:.2f}")
    row("inferences / s at 400 MHz", 1 / T["v2"], 1 / T["v3"], "{:.0f}")
    for n in R["v2"][2]:
        n3 = n.replace("(24 x 1024x64)", "(48 x 512x64)")
        lab = n.replace("(24 x 1024x64)", "(v2 24 x 1024x64, v3 48 x 512x64)")
        row(f"&nbsp;&nbsp;{lab}: uJ / inference", R["v2"][2][n] * T["v2"] * 1e6, R["v3"][2][n3] * T["v3"] * 1e6, "{:.3f}")
    pa = {v: R[v][2]["PE array (u_array)"] * T[v] / BLOCKS * 1e12 for v in VER}
    row("PE array energy pJ / QC block", pa["v2"], pa["v3"], "{:.3f}")
    for k, lab in (("act", "act"), ("wgt", "weight"), ("par", "param")):
        a, b = R["v2"][0]["dat"][energy.MACRO[k] if k != "act" else VER["v2"][4]], R["v3"][0]["dat"][energy.MACRO[k] if k != "act" else VER["v3"][4]]
        row(f"{lab} macros: 64/72/80-b macro reads / image (all instances)", a["reads_pc"] * VER["v2"][2], b["reads_pc"] * VER["v3"][2], "{:.0f}")
        row(f"{lab} macros: uJ / inference (datatable dynamic)", a["P_dyn"] * T["v2"] * 1e6, b["P_dyn"] * T["v3"] * 1e6, "{:.3f}")
    for k, lab, f in (("total", "area mm2 (total)", "{:.3f}"), ("macro", "macro mm2", "{:.3f}"), ("logic", "logic mm2", "{:.3f}"),
                      ("kge", "logic kGE", "{:.1f}"), ("arr", "PE array kGE", "{:.1f}"), ("pe", "one PE kGE", "{:.2f}"),
                      ("ppu", "PPU kGE", "{:.1f}"), ("ss", "fmax ss MHz", "{:.1f}"), ("tt", "fmax tt MHz", "{:.1f}"),
                      ("ff", "fmax ff MHz", "{:.1f}")):
        row(lab, I["v2"][k], I["v3"][k], f)
    G = {v: pe_groups(v) for v in VER}
    if G["v2"] and G["v3"]:
        print(f"\nPE-internal power (pe_power.tcl, per PE averaged over the 64 PEs) and energy per QC block "
              f"(= P_PE x T_image x 64 / {BLOCKS}):\n")
        print("| group | v2 uW / PE | v3 uW / PE | v2 fJ / block | v3 fJ / block | v3 / v2 per block |")
        print("|---|---|---|---|---|---|")
        tot = {v: 0.0 for v in VER}
        for g, lab in GROUPS.items():
            e = {v: G[v].get(g, 0.0) * T[v] * 64 / BLOCKS * 1e15 for v in VER}
            for v in VER:
                tot[v] += e[v]
            print(f"| {lab} | {G['v2'].get(g, 0) * 1e6:.1f} | {G['v3'].get(g, 0) * 1e6:.1f} | {e['v2']:.1f} | {e['v3']:.1f} | "
                  f"{e['v3'] / e['v2'] if e['v2'] else float('nan'):.3f} |")
        s = {v: sum(G[v].get(g, 0) for g in GROUPS) for v in VER}
        print(f"| **PE total** | {s['v2'] * 1e6:.1f} | {s['v3'] * 1e6:.1f} | {tot['v2']:.1f} | {tot['v3']:.1f} | "
              f"{tot['v3'] / tot['v2']:.3f} |")
        comp = {v: sum(G[v].get(g, 0) for g in ("rot", "tadd", "accadd")) * T[v] * 64 / BLOCKS * 1e15 for v in VER}
        print(f"\nPE combinational (rot + tadd + accadd) fJ / block: v2 {comp['v2']:.1f}, v3 {comp['v3']:.1f} "
              f"({comp['v3'] / comp['v2']:.3f})")
    print("\nPredictions (ARCH.md v3) vs measured: image energy ~70 uJ -> "
          f"{E['v3']:.1f} uJ ({100 * (E['v3'] / 70 - 1):+.1f} %); cycles x0.53 -> x{VER['v3'][2] / VER['v2'][2]:.3f}; "
          f"PE energy per block x0.7 -> x{pa['v3'] / pa['v2']:.3f} (PE array incl. its input nets); "
          f"leakage + control x0.55 -> leakage energy x{R['v3'][1][2] * T['v3'] / (R['v2'][1][2] * T['v2']):.3f}")


if __name__ == "__main__":
    main()
