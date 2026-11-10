#!/usr/bin/env python3
"""v4 (16 pixel rows) tables of QC18-ACC for results/v4.md, v3 as the reference:
    python3 qc18acc/power/report4.py EXPORT_DIR [mode=sdf] [period=2.5] > tables.md
EXPORT_DIR: a compile4 export (desc / weight images) for the executed-op count (compile4.ops).
Inputs: impl/results/qa{3,4}_w3.3/{area.txt, timing.txt, area_groups.txt} (DC / PT, [S]); results/power_v{3,4}
(PTPX on the SDF SAIF, energy.py +dat = macro access energy from the datatables, [S] + [Mod]); cycles per image from
RTL = GLS ([M]).  Labels: M measured (simulation counters, bit-exact runs), S synthesis estimate (DC / PT / PTPX on the
pre-route netlist, WLM, ideal clock), Mod model (cycle model, datatable macro energy, op counting from the weight image).
Executed ops (ARCH v4 addendum): ops = 2 x executed MACs, 8 MACs per nonzero QC term; peak = PEs x Kb x 16 MACs per
cycle; workload average = executed MACs per image (weight image) x images / s; TOPS / mm2 on the full pre-route area.
"""
import os
import re
import sys
from pathlib import Path

Q = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Q.parent))
sys.path.insert(0, str(Q / "power"))
import energy  # noqa: E402
from qc18acc.compile4.ops import executed  # noqa: E402

exp = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else "sdf"
per = sys.argv[3] if len(sys.argv) > 3 else "2.5"
DENSE_MACS = 555417600 + 5120
V = {"v3": dict(tag="qa3_w3.3", power="power_v3", cyc=81438, pes=64, act="qa_act_512x64m4"),
     "v4": dict(tag="qa4_w3.3", power="power_v4", cyc=42360, pes=128, act="qa_act_256x128m2")}


def groups(tag):
    g, fan = {}, {}
    for line in (Q / "impl" / "results" / tag / "area_groups.txt").read_text().splitlines():
        if line.startswith("#"):
            continue
        if line.startswith("fanin:"):
            m = re.match(r"fanin:(\S+) pin (\S+) startpoints (\d+) macro_pins (\d+) other (\d+)", line)
            fan[m[1]] = (m[2], int(m[3]), int(m[4]), int(m[5]))
            continue
        k, a, n = line.split()
        g[k] = (float(a), int(n))
    return g, fan


def timing(tag):
    t = (Q / "impl" / "results" / tag / "timing.txt").read_text()
    f = {c: float(v) for c, v in re.findall(r"^(ss|tt|ff) clock qa_clk .* fmax_mhz (\S+)", t, re.M)}
    path = {c: (s, e) for c, s, e in re.findall(r"^(ss|tt|ff) clock qa_clk .* path (\S+) -> (\S+)", t, re.M)}
    cls = {c: (int(a), int(b)) for c, a, b in re.findall(r"^(ss|tt|ff) path_class start_at_macro (\d) end_at_macro (\d)", t, re.M)}
    return f, path, cls


def area_total(tag):
    t = (Q / "impl" / "results" / tag / "area.txt").read_text()
    return float(re.search(r"total_mm2 (\S+)", t)[1]), float(re.search(r"logic_kGE (\S+)", t)[1])


def sumg(g, *keys):
    return sum(g.get(k, (0.0, 0))[0] for k in keys), sum(g.get(k, (0.0, 0))[1] for k in keys)


def breakdown(g):
    """[(group, sub, um2)]: macros, PE (acc regs, adders, operand regs, clock, other), PPU, xbar, control."""
    rows = [("macros", "activation macros", sumg(g, "macro:qa_act")[0]),
            ("macros", "weight macros", sumg(g, "macro:qa_wgt")[0]),
            ("macros", "param + descriptor macros", sumg(g, "macro:qa_par", "macro:qa_dsc")[0]),
            ("macros", "registered boundary (output regs, read flags, macro ICGs, input flops; wrappers)",
             sumg(g, "act:out_regs", "act:in_flops", "wmem", "pmem", "desc")[0]),
            ("PE", "acc regs (accumulators + shadows)", sumg(g, "pe:acc_regs", "pe:shadow_regs")[0]),
            ("PE", "adders (fused trits + 4 terms + accumulate)", sumg(g, "pe:adders")[0]),
            ("PE", "operand regs (window rows + code register)", sumg(g, "xbar:window", "xbar:code")[0]),
            ("PE", "clock (DC clock gates in the PEs)", sumg(g, "pe:clock")[0]),
            ("PE", "rotators", sumg(g, "pe:rotators")[0]),
            ("PE", "capture / shift-in muxes, array rest", sumg(g, "pe:muxes", "array:rest")[0]),
            ("PPU", "PPU lanes (+ drain: param RF, addresses)", sumg(g, "ppu", "ppu_v3", "drain")[0]),
            ("xbar", "bank select, stage A, residual + write paths, delay lines, act-port muxes",
             sumg(g, "act:bank_select", "xbar:stage_a", "act:res_path", "act:res_path2", "act:write_path",
                  "act:write_wd", "xbar:ctrl", "act:other")[0]),
            ("control", "seq, AGU, host, head, top glue", sumg(g, "seq", "agu", "host", "head", "glue")[0])]
    return rows


def main():
    ex = executed(exp)
    macs = ex["macs"]
    print(f"Executed MACs / image (weight image, Mod): conv {ex['conv_macs']} + FC {ex['fc_macs']} = {macs} "
          f"(ops {2 * macs}); dense-equivalent {DENSE_MACS} MACs (x{DENSE_MACS / macs:.2f}).\n")
    G = {v: groups(d["tag"]) for v, d in V.items()}
    T = {v: timing(d["tag"]) for v, d in V.items()}
    A = {v: area_total(d["tag"]) for v, d in V.items()}

    # ---- throughput / TOPS
    print("| version | clock | cycles / image [M] | img / s | peak executed TOPS | workload-average executed TOPS | "
          "peak TOPS / mm2 | average TOPS / mm2 | dense-eq. TOPS (secondary) | dense-eq. TOPS / mm2 |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for v, d in V.items():
        mm2 = A[v][0]
        peak_ops = d["pes"] * 2 * 16 * 2
        for lab, f in (("400 MHz (tt, energy clock)", 400.0), (f"tt fmax {T[v][0]['tt']:.1f} MHz [S]", T[v][0]["tt"]),
                       (f"ss fmax {T[v][0]['ss']:.1f} MHz [S]", T[v][0]["ss"])):
            ips = f * 1e6 / d["cyc"]
            pk, av, de = peak_ops * f * 1e6 / 1e12, 2 * macs * ips / 1e12, 2 * DENSE_MACS * ips / 1e12
            print(f"| {v} | {lab} | {d['cyc']} | {ips:.0f} | {pk:.3f} | {av:.3f} | {pk / mm2:.3f} | {av / mm2:.3f} | "
                  f"{de:.2f} | {de / mm2:.2f} |")
    print(f"\nArea: v3 {A['v3'][0]:.3f} mm2, v4 {A['v4'][0]:.3f} mm2 (pre-route cell + macro area, [S]).  Utilisation "
          f"(average / peak executed): v3 {2 * macs / V['v3']['cyc'] / (64 * 64):.3f}, v4 "
          f"{2 * macs / V['v4']['cyc'] / (128 * 64):.3f}.\n")

    # ---- area per peak executed MAC / cycle
    print("Area per peak executed MAC / cycle (v3: 64 PEs x 2 x 16 = 2048 MAC / cycle; v4: 128 x 2 x 16 = 4096) [S]:\n")
    print("| group | part | v3 um2 | v3 um2 / (MAC/cycle) | v4 um2 | v4 um2 / (MAC/cycle) | v4 share |")
    print("|---|---|---|---|---|---|---|")
    b3, b4 = breakdown(G["v3"][0]), breakdown(G["v4"][0])
    tot4 = sum(r[2] for r in b4)
    sums = {}
    for (gr, part, a3), (_, _, a4) in zip(b3, b4):
        sums.setdefault(gr, [0.0, 0.0])
        sums[gr][0] += a3
        sums[gr][1] += a4
        print(f"| {gr} | {part} | {a3:.0f} | {a3 / 2048:.1f} | {a4:.0f} | {a4 / 4096:.1f} | {100 * a4 / tot4:.1f} % |")
    for gr, (a3, a4) in sums.items():
        print(f"| **{gr}** | | {a3:.0f} | {a3 / 2048:.1f} | {a4:.0f} | {a4 / 4096:.1f} | {100 * a4 / tot4:.1f} % |")
    t3 = sum(r[2] for r in b3)
    print(f"| **total** | | {t3:.0f} | {t3 / 2048:.1f} | {tot4:.0f} | {tot4 / 4096:.1f} | 100 % |")

    # ---- xbar
    print("\nActivation crossbar [S] (cells = leaf cells; v3: u_xbar + the act-port logic of u_act outside the macro "
          "wrappers; v4: the same plus the new bank-select / stage-A / residual / write stages):\n")
    print("| part | v3 cells | v3 um2 | v4 cells | v4 um2 |")
    print("|---|---|---|---|---|")
    keys = [("window registers", ["xbar:window"]), ("stage A registers", ["xbar:stage_a"]),
            ("bank-select registers", ["act:bank_select"]), ("code register", ["xbar:code"]),
            ("xbar control / delay lines / window muxes", ["xbar:ctrl"]),
            ("residual read path", ["act:res_path", "act:res_path2"]), ("write path", ["act:write_path", "act:write_wd"]),
            ("act-port logic (address / request muxes, v3 read muxes)", ["act:other"])]
    t = {"v3": [0, 0.0], "v4": [0, 0.0]}
    for name, ks in keys:
        a3, n3 = sumg(G["v3"][0], *ks)
        a4, n4 = sumg(G["v4"][0], *ks)
        t["v3"][0] += n3; t["v3"][1] += a3; t["v4"][0] += n4; t["v4"][1] += a4
        print(f"| {name} | {n3} | {a3:.0f} | {n4} | {a4:.0f} |")
    print(f"| **total** | {t['v3'][0]} | {t['v3'][1]:.0f} | {t['v4'][0]} | {t['v4'][1]:.0f} |")
    print("\nFan-in (start points of the fan-in cone of one register D pin, PT all_fanin; macro pins = macro Q pins) [S]:\n")
    print("| version | stage | pin | start points | of which macro Q pins |")
    print("|---|---|---|---|---|")
    for v in V:
        for k, (pin, n, nm, no) in G[v][1].items():
            print(f"| {v} | {k} | `{pin}` | {n} | {nm} |")

    # ---- timing
    print("\nPre-route timing (DC 3.3 ns at ss, PT ideal clock, WLM) [S]:\n")
    print("| version | corner | fmax MHz | critical path | starts / ends at a macro |")
    print("|---|---|---|---|---|")
    for v in V:
        f, p, c = T[v]
        for k in ("ss", "tt", "ff"):
            cl = c.get(k) or (int("g_mac" in p[k][0]), int("g_mac" in p[k][1]))     # v3: from the pin names
            print(f"| {v} | {k} | {f[k]:.1f} | `{p[k][0]}` -> `{p[k][1]}` | {cl[0]} / {cl[1]} |")

    # ---- energy
    if not all((Q / "results" / d["power"] / f"{mode}_{per}ns.txt").exists() for d in V.values()):
        print("\n(no power results yet)")
        return
    print("\nEnergy at 400 MHz tt (PTPX on the SDF SAIF of image 0 [S], macro access energy +dat [Mod]):\n")
    print("| quantity | v3 | v4 | v4 / v3 |")
    print("|---|---|---|---|")
    res = {}
    for v, d in V.items():
        energy.R = Q / "results" / d["power"]
        energy.CYCLES = d["cyc"]
        energy.V4 = v == "v4"
        energy.V3 = True
        energy.MACRO["act"] = d["act"]
        r = energy.load(mode, per)
        pt, corr, leak = energy.summary(r)
        t = d["cyc"] * float(per) * 1e-9
        res[v] = dict(mw=corr * 1e3, uj=corr * t * 1e6, leak=leak * 1e3, leak_uj=leak * t * 1e6,
                      blocks={n: c * t * 1e6 for n, _, c, _ in energy.blocks(r)}, pj_mac=corr * t / macs * 1e12)
    rows = [("power mW (+dat)", "mw", "{:.1f}"), ("energy uJ / inference (+dat)", "uj", "{:.2f}"),
            ("leakage mW", "leak", "{:.2f}"), ("leakage uJ / inference", "leak_uj", "{:.2f}"),
            ("pJ / executed MAC", "pj_mac", "{:.4f}")]
    for lab, k, fm in rows:
        a, b = res["v3"][k], res["v4"][k]
        print(f"| {lab} | {fm.format(a)} | {fm.format(b)} | {b / a:.3f} |")
    for n in res["v4"]["blocks"]:
        a = res["v3"]["blocks"].get(n.replace("48 x 256x128", "48 x 512x64"), float("nan"))
        b = res["v4"]["blocks"][n]
        print(f"| &nbsp;&nbsp;{n}: uJ / inference | {a:.3f} | {b:.3f} | {b / a:.3f} |")
    blk = 8724480                                          # QC blocks per image (stem odd zero blocks not counted)
    pe = {v: res[v]["blocks"]["PE array (u_array)"] / blk * 1e6 for v in V}
    print(f"| PE array pJ / QC block | {pe['v3']:.3f} | {pe['v4']:.3f} | {pe['v4'] / pe['v3']:.3f} |")
    ctl = "AGU + xbar + seq + host + top glue"
    xb = {v: res[v]["blocks"][ctl] + res[v]["blocks"]["act buffer logic (hold regs, port muxes)"] for v in V}
    print(f"| control + act-buffer logic (AGU, xbar, seq, host, glue, act-port / boundary / xbar stages) uJ | "
          f"{xb['v3']:.3f} | {xb['v4']:.3f} | {xb['v4'] / xb['v3']:.3f} |")
    print(f"| executed ops / J (TOPS / W) | {2 * macs / res['v3']['uj'] / 1e6:.2f} | {2 * macs / res['v4']['uj'] / 1e6:.2f} | "
          f"{res['v3']['uj'] / res['v4']['uj']:.3f} |")
    # PE-internal groups per QC block (pe_power.tcl: per-PE average W)
    print("\nPE-internal power (pe_power.tcl, per-PE average) and energy per QC block (P_PE x T_image x PEs / 8 724 480) [S]:\n")
    print("| group | v3 uW / PE | v4 uW / PE | v3 fJ / block | v4 fJ / block | v4 / v3 |")
    print("|---|---|---|---|---|---|")
    G = {}
    for v, d in V.items():
        f = Q / "results" / d["power"] / f"{mode}_{per}ns_pe.txt"
        G[v] = {l.split()[0]: float(l.split()[4]) for l in f.read_text().splitlines() if l.startswith("pe:") and len(l.split()) == 5}
    names = dict(rot="rotators (4 x 8-lane)", accadd="fused trits + 4 terms + accumulate (u_acc)",
                 accreg="accumulator registers (data part)", shreg="shadow registers (data part)",
                 top="capture / shift-in muxes", clock="clock: DC clock gates + register clock pins")
    tot = {v: 0.0 for v in V}
    for g, n in names.items():
        e = {}
        for v, d in V.items():
            t = d["cyc"] * float(per) * 1e-9
            e[v] = G[v][f"pe:{g}"] * t * d["pes"] / blk * 1e15
            tot[v] += e[v]
        print(f"| {n} | {G['v3'][f'pe:{g}'] * 1e6:.1f} | {G['v4'][f'pe:{g}'] * 1e6:.1f} | {e['v3']:.1f} | {e['v4']:.1f} | "
              f"{e['v4'] / e['v3']:.3f} |")
    print(f"| **PE total** | | | {tot['v3']:.1f} | {tot['v4']:.1f} | {tot['v4'] / tot['v3']:.3f} |")


if __name__ == "__main__":
    main()
