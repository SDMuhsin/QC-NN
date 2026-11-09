#!/usr/bin/env python3
"""QC18-ACC power / energy tables from the PrimeTime PX summaries of qc18acc/power/power.sh.

    python3 qc18acc/power/energy.py [results/power dir] > section.md

Reads <mode>_<p>ns.txt (power groups), _blocks.txt (per block), _macros.txt (datatable macro model) for every
mode (sdf, zd) and period present.  Two totals per run:
  PT      PrimeTime as is (macro dynamic = the .lib pin energies only: the macro CLK access energy tables are 0)
  +dat    the macros' internal power replaced by the datatable access model (macro_dat.py: reads, writes and
          deselected clock edges x datatable energy; macro leakage and the switching of the macro output nets as PT)
Energy per inference = P x CYCLES x period (START..DONE of image 0, RTL = GLS cycle count); per dense-equivalent MAC
(convs 555 417 600 + FC 5 120) and per QC addition (127 295 232 per image, qc18/results/s8kd_s0.md).
"""
import re
import sys
from pathlib import Path

CYCLES = 159982
MACS = 555417600 + 5120
ADDS = 127295232
R = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "results" / "power")
MACRO = dict(act="qa_act_1024x64m8", wgt="qa_wgt_4096x80m8", par="qa_par_4096x72m8", dsc="qa_dsc_256x32m2")


def load(mode, p):
    t = (R / f"{mode}_{p}ns.txt").read_text()
    grp = {m[0]: [float(x) for x in m[1:5]] for m in
           re.findall(r"^(clock_network|register|combinational|memory)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", t, re.M)}
    tot = {k: float(v) for k, v in re.findall(r"^\s*(Net Switching|Cell Internal|Cell Leakage) Power\s*=\s*(\S+)", t, re.M)}
    b = {}
    for line in (R / f"{mode}_{p}ns_blocks.txt").read_text().splitlines():
        if line.startswith("#"):
            continue
        w = line.split()
        b[w[0].split(":", 1)[1]] = [float(x) for x in w[1:5]]       # internal switching leakage total
    dat = {}
    for line in (R / f"{mode}_{p}ns_macros.txt").read_text().splitlines():
        m = re.match(r"datmacro:(qa_\S+) (.*)", line)
        if m:
            w = m.group(2).split()
            dat[m.group(1)] = {w[i]: float(w[i + 1]) for i in range(0, len(w), 2)}
    return dict(grp=grp, tot=tot, b=b, dat=dat, p=float(p))


def blocks(r):
    """[(name, PT W, +dat W, leakage W)] in report order."""
    b, d = r["b"], r["dat"]
    sub = lambda x, y: [u - v for u, v in zip(x, y)]
    add = lambda *xs: [sum(v) for v in zip(*xs)]
    rows = [("PE array (u_array)", b["u_array"]), ("PPU (u_ppu)", b["u_ppu"]), ("drain (u_drain)", b["u_drain"]),
            ("head (u_head)", b["u_head"]),
            ("AGU + xbar + seq + host + top glue", add(b["u_agu"], b["u_xbar"], b["u_seq"], b["u_host"], b["top_leaf_cells"])),
            ("act buffer logic (hold regs, port muxes)", sub(b["u_act"], b[MACRO["act"]])),
            ("weight / param / desc wrapper logic", add(sub(b["u_wmem"], b[MACRO["wgt"]]), sub(b["u_pmem"], b[MACRO["par"]]),
                                                         sub(b["u_desc"], b[MACRO["dsc"]])))]
    out = [(n, v[3], v[3], v[2]) for n, v in rows]
    for k, n in (("act", "activation macros (24 x 1024x64)"), ("wgt", "weight macros (6 x 4096x80)"),
                 ("par", "param macros (2 x 4096x72)"), ("dsc", "descriptor macro (256x32)")):
        v = b[MACRO[k]]
        out.append((n, v[3], v[3] - v[0] + d[MACRO[k]]["P_dyn"], v[2]))
    return out


def summary(r):
    d = r["b"]["qa_top"]                                  # sum over all leaf cells (full precision)
    pt, leak = d[3], d[2]
    corr = pt + sum(r["dat"][m]["P_dyn"] - r["b"][m][0] for m in MACRO.values())
    return pt, corr, leak


def mw(x):
    return f"{x * 1e3:.2f}"


def main():
    runs = {}
    for f in sorted(R.glob("*ns.txt")):
        mode, p = re.match(r"(\w+?)_([\d.]+)ns\.txt", f.name).groups()
        runs[(mode, p)] = load(mode, p)
    print("| SAIF | clock | PT total mW | int / switch / leak mW | +dat total mW | leakage share (+dat) | "
          "uJ / inference PT / +dat | pJ / dense MAC (+dat) | pJ / QC add (+dat) |")
    print("|---|---|---|---|---|---|---|---|---|")
    for (mode, p), r in sorted(runs.items(), key=lambda k: (k[0][0] != "sdf", float(k[0][1]))):
        pt, corr, leak = summary(r)
        t = CYCLES * r["p"] * 1e-9
        print(f"| {mode} | {p} ns ({1e3 / r['p']:.0f} MHz) | {mw(pt)} | {mw(r['b']['qa_top'][0])} / "
              f"{mw(r['b']['qa_top'][1])} / {mw(leak)} | {mw(corr)} | {100 * leak / pt:.1f} % ({100 * leak / corr:.1f} %) | "
              f"{pt * t * 1e6:.2f} / {corr * t * 1e6:.2f} | {corr * t / MACS * 1e12:.4f} | {corr * t / ADDS * 1e12:.3f} |")
    print()
    for (mode, p), r in sorted(runs.items(), key=lambda k: (k[0][0] != "sdf", float(k[0][1]))):
        if p != "2.5":
            continue
        pt, corr, _ = summary(r)
        print(f"\n{mode} SAIF, {p} ns: blocks (PT total; +dat: macro internal power from the datatable model)\n")
        print("| block | PT mW | % PT | +dat mW | % +dat | leakage mW |")
        print("|---|---|---|---|---|---|")
        for n, a, c, l in blocks(r):
            print(f"| {n} | {mw(a)} | {100 * a / pt:.1f} | {mw(c)} | {100 * c / corr:.1f} | {mw(l)} |")
        print(f"| **total** | {mw(pt)} | 100 | {mw(corr)} | 100 | {mw(r['b']['qa_top'][2])} |")
        g = r["grp"]
        print(f"\nPT power groups (cross-cutting; mW total): clock_network {mw(g['clock_network'][3])} "
              f"(ICGs + register clock pins + clock nets, ideal clock, no CTS buffers; internal {mw(g['clock_network'][0])}, "
              f"switching {mw(g['clock_network'][1])}), register {mw(g['register'][3])}, combinational "
              f"{mw(g['combinational'][3])}, memory {mw(g['memory'][3])}.")
        print("\nmacro datatable model (per cycle, all instances of a type):\n")
        print("| macro | reads / cycle | writes / cycle | deselected clocks / cycle | E read / write / desel pJ | P read / write / desel mW |")
        print("|---|---|---|---|---|---|")
        for m, d in r["dat"].items():
            print(f"| {m} (x{int(d['n'])}) | {d['reads_pc']:.3f} | {d['writes_pc']:.3f} | {d['desel_pc']:.3f} | "
                  f"{d['E_read']:.1f} / {d['E_write']:.1f} / {d['E_desel']:.2f} | {mw(d['P_read'])} / {mw(d['P_write'])} / {mw(d['P_desel'])} |")
    if ("sdf", "2.5") in runs and ("zd", "2.5") in runs:
        s, z = runs[("sdf", "2.5")], runs[("zd", "2.5")]
        dyn = lambda r: r["b"]["qa_top"][0] + r["b"]["qa_top"][1]
        print(f"\nGlitch factor SDF / zd (PT dynamic power, 2.5 ns): design {dyn(s) / dyn(z):.3f}; per block:")
        for (n, a, _, la), (_, b, _, lb) in zip(blocks(s), blocks(z)):
            if b - lb > 1e-5:
                print(f"  {n} {(a - la) / (b - lb):.3f}", end=";")
        print()


if __name__ == "__main__":
    main()
