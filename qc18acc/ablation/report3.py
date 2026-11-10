"""QC18-ACC array ablation at Kb = 2 (v3 array geometry):  python3 -m qc18acc.ablation.report3 <L> <results_dir>

L = local Kb = 2 ablation dir (run.sh with QAB_KB=2: vec/stats.txt, rtl.txt, out/<v>/ = the hosts' summaries).
Writes the "Kb = 2" section (section 7) of <results_dir>/ablation.md (sections 1-6 = Kb = 1, report.py, are kept)
and copies the summaries to <results_dir>/ablation_kb2/.  The Kb = 1 numbers of the comparison tables are read from
<results_dir>/ablation/ (the Kb = 1 summaries).  Measured: array area / fmax (DC + PT), GLS check, PT PX power of the
PE busy window.  The system part is a MODEL built on the measured v3 numbers of results/power_v3 (+dat) and the v3
area (impl/results/qa3_w3.3).
"""
import glob
import os
import re
import shutil
import sys

V = ["qc", "tern", "int8"]
NAME = {"qc": "QC", "tern": "TERNARY", "int8": "INT8"}
WB = {"qc": 20, "tern": 256, "int8": 1024}         # weight bits per column per cycle (two blocks)
WB1 = {"qc": 10, "tern": 128, "int8": 512}
ACC = {"qc": 20, "tern": 21, "int8": 32}
PTS = {"qc": ["qc_L2", "qc_L4"], "tern": ["tern_L2", "tern_L4"], "int8": ["int8_L2", "int8_L4", "int8c_L2", "int8c_L4"]}
LAY = {"L2": "blocks.3.c1 (layer 2, S = 72 pair steps / tile, 16 tiles)", "L4": "blocks.7.c1 (layer 4, S = 288, 4 tiles)"}
T_CLK = 2.5e-9
CYC = 81438                                        # v3 START..DONE cycles / inference (results/v3.md)
HERE = os.path.dirname(os.path.abspath(__file__))
V3 = os.path.join(HERE, "..", "results", "power_v3")
V3A = os.path.join(HERE, "..", "impl", "results", "qa3_w3.3", "area.txt")
MARK = "## 7. Kb = 2"


def f(x, n=2):
    return f"{x:.{n}f}"


def rows_of(fn):
    rows = {}
    for line in open(fn):
        if line.startswith("#"):
            continue
        t = line.split()
        rows[t[0]] = [float(x) for x in t[2:6]]
    return rows


def gls(fn):
    t = open(fn).read()
    m = re.search(r"QAB_RESULT (\w+) tiles (\d+) rows_checked (\d+) bad (\d+) steps (\d+)", t)
    tv = int(re.search(r"timing_violations (\d+)", t).group(1))
    return dict(ok=m.group(1), rows=int(m.group(3)), bad=int(m.group(4)), steps=int(m.group(5)), tviol=tv)


DP = ("u_rot1", "u_rot2", "u_rot3", "u_rot4", "u_tadd", "u_acc", "u_dot")


def power(cells_fn):
    """array / non-array / design power (W: int, sw, leak, total), PE total and its datapath part (rotators +
    trit / term adds + accumulate add, or the fused u_acc / u_dot + u_acc), summed over the 64 PEs."""
    if not os.path.exists(cells_fn):
        return None
    rows = rows_of(cells_fn)
    arr = [k for k in rows if k.endswith("u_array")][0]
    pe = [k for k in rows if k.startswith(arr + "/") and k.endswith("u_pe")]
    dp = [k for k in rows if k.startswith(arr + "/") and k.rsplit("/", 1)[-1] in DP
          and k.rsplit("/", 1)[0].endswith("u_pe")]
    # fused / generate-scoped sub-blocks (g_t / g_i) of the ablation PEs
    dp += [k for k in rows if k.startswith(arr + "/") and re.search(r"u_pe/g_[ti]_?u_(acc|dot)$|u_pe/g_[ti]/u_(acc|dot)$", k)]
    pet = [sum(rows[k][i] for k in pe) for i in range(4)]
    dpt = [sum(rows[k][i] for k in set(dp)) for i in range(4)]
    return dict(arr=rows[arr], non=rows["NONARRAY_LEAF"], des=rows["DESIGN"], pe=pet, dp=dpt)


def v3_numbers():
    blk = {}
    for line in open(os.path.join(V3, "sdf_2.5ns_blocks.txt")):
        if line.startswith("#"):
            continue
        t = line.split()
        blk[t[0]] = [float(x) for x in t[1:5]]
    dat = {}
    for line in open(os.path.join(V3, "sdf_2.5ns_macros.txt")):
        m = re.match(r"datmacro:(\S+) n (\d+) .*E_read (\S+) .* P_dyn (\S+) leak_dat (\S+)", line)
        if m:
            dat[m.group(1)] = dict(n=int(m.group(2)), e_read=float(m.group(3)), p_dyn=float(m.group(4)), leak=float(m.group(5)))
    macros = [k for k in blk if k.startswith("macro:")]
    p_dat = blk["design:qa_top"][3] - sum(blk[k][0] for k in macros) + sum(d["p_dyn"] for d in dat.values())
    wg = "qa_wgt_4096x80m8"
    p_w = blk["macro:" + wg][3] - blk["macro:" + wg][0] + dat[wg]["p_dyn"]
    p_arr = blk["hier:u_array"][3]
    area = {}
    for line in open(V3A):
        m = re.match(r"(pe_array|weight SRAM).*?\s(\d+)\s+(\d+)\s+(\d+)\s+\S+\s+\S+$", line)
        if m:
            area[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
        m = re.match(r"total_um2 (\d+)", line)
        if m:
            area["total"] = int(m.group(1))
    return dict(p_dat=p_dat, p_w=p_w, p_arr=p_arr, wleak=blk["macro:" + wg][2] / dat[wg]["n"],
                e_read=dat[wg]["e_read"], nw=dat[wg]["n"], area=area)


def energies(P, Z, pts, bpc):
    """per point: array pJ / block-op (bpc block-ops per PE-cycle), weight-input register delta vs QC, leakage."""
    E = {}
    for pt in pts:
        p = P[pt]
        l = pt.split("_")[1]
        q = P["qc_" + l]
        E[pt] = dict(arr=p["arr"][3] * T_CLK / 64 / bpc * 1e12, wd=(p["non"][3] - q["non"][3]) * T_CLK / 64 / bpc * 1e12,
                     leak=p["arr"][2] + p["non"][2] - q["non"][2],
                     dp=p["dp"][3] * T_CLK / 64 / bpc * 1e12, pe=p["pe"][3] * T_CLK / 64 / bpc * 1e12)
        E[pt]["regs"] = E[pt]["pe"] - E[pt]["dp"]
        E[pt]["chain"] = E[pt]["arr"] - E[pt]["pe"]
        if Z and Z.get(pt):
            E[pt]["zarr"] = Z[pt]["arr"][3] * T_CLK / 64 / bpc * 1e12
            E[pt]["zwd"] = (Z[pt]["non"][3] - Z["qc_" + l]["non"][3]) * T_CLK / 64 / bpc * 1e12
    return E


def mean(E, v, k):
    return sum(E[f"{v}_{l}"][k] for l in ("L2", "L4")) / 2


def main():
    L, R = sys.argv[1], sys.argv[2]
    st = open(os.path.join(L, "vec", "stats.txt")).read()
    sched = dict(re.findall(r"(\w+) (\d+)", st.splitlines()[0].replace("schedule ", "")))
    steps, bops = int(sched["array_steps"]), int(sched["block_ops"])
    bits = {"qc": int(sched["qc_bits"]), "tern": int(sched["tern_bits"]), "int8": int(sched["int8_bits"]),
            "sp28": int(sched["sp28_bits"])}
    S = {v: syn_dir(os.path.join(L, "out", v, f"qab3_{v}_w3.3")) for v in V}
    G = {pt: gls(os.path.join(L, "out", v, f"gls_{pt}.txt")) for v in V for pt in PTS[v]}
    P = {pt: power(os.path.join(L, "out", v, f"power_{pt}_cells.txt")) for v in V for pt in PTS[v]}
    Z = {pt: power(os.path.join(L, "out", v, f"power_zd_{pt}_cells.txt")) for v in V for pt in PTS[v]}
    zd = all(Z.values())
    rtl = open(os.path.join(L, "rtl.txt")).read()
    # Kb = 1 (results/ablation/)
    R1 = os.path.join(R, "ablation")
    S1 = {v: syn_dir(R1, f"qab_{v}_w3.3_") for v in V}
    P1 = {pt: power(os.path.join(R1, f"power_{pt}_cells.txt")) for v in V for pt in PTS[v]}
    E1 = energies(P1, None, [pt for v in V for pt in PTS[v]], 1)
    E = energies(P, Z if zd else None, [pt for v in V for pt in PTS[v]], 2)
    w3 = v3_numbers()
    out = []
    o = out.append
    o(MARK + " (v3 array geometry: two 8x8 blocks per PE per cycle)\n")
    o("Same method as sections 1-6, on the v3 array: `QAB_KB=2 qc18acc/ablation/run.sh vec | rtl | start syn | sdf | "
      "gls | power | fetch | report` (`vectors3.py`, `rtl/qab3.f`, `report3.py`); host work dirs `/tmp/ckp908/qc18acc/abl3`; "
      "summaries `results/ablation_kb2/`.  Labels: **[S]** synthesis estimate (DC / PT, WLM, pre-CTS), **[M]** "
      "measured in simulation (Verilator / VCS GLS), **[P]** PT PX power of the synthesised netlist with the GLS SAIF, "
      "**[Mo]** model.\n")
    o("### 7.1 Variants\n")
    o("| | QC (v3, unchanged) | TERNARY | INT8 |\n|---|---|---|---|")
    o("| PE RTL | `hw3/rtl/qa_pe.sv` (4 rotators, fused trits + 4 terms + accumulate, `qa_pe_acc4`) | "
      "`ablation/rtl/qab3_pe.sv` V=1: 16 trit-selects + accumulate as ONE sum per lane | V=2: 16 signed 8x8 products + "
      "accumulate as ONE sum per lane |")
    o("| weight bits / PE-cycle (per column, 2 blocks) | 20 | 256 (2 x 64 trits x 2 b) | 1024 (2 x 64 x int8) |")
    o("| weight bits into the array / cycle | 160 | 2048 | 8192 |")
    o("| x bits into the array / cycle | 1024 | 1024 | 1024 |")
    o("| accumulator | 20 b | 21 b | 32 b |")
    o("\nAs v3 does for QC, the TERNARY / INT8 PEs at Kb = 2 compute the whole lane update (16 terms + accumulator) in "
      "one combinational sum (one CSA tree for DC; at Kb = 1 they had a separate u_dot and u_acc, as the v2 QC PE).  "
      "Everything else as v3: 8 x 8 PEs, rows = 8 output pixels with a 128-b pair word (even / odd input group), "
      "output-stationary accumulators, shadow capture / chain, the input pipeline register (`rtl/qab3_top.sv`).\n")
    o("Stream (`vectors3.py`): s8kd_s0 test image 0, the REAL v3 array inputs (v3 golden model `compile3` up to the "
      "pass, then `compile3.golden.gather_window`: v3 tap order kh, pair j, kw; even block = v2 tap (kh, kw, 2j), odd = "
      "(kh, kw, 2j + 1)).  Same layers and tiles as Kb = 1, i.e. the same 8x8 block-ops in half the steps (1152 steps "
      "per point); golden check: QC sums == the v3 golden pass accumulators and == the Kb = 1 sums:")
    for l in ("L2", "L4"):
        line = [x for x in st.splitlines() if x.startswith(l + " ")][0]
        o(f"- {l} = {LAY[l]}: {line.split(' ', 2)[2]}")
    o("")
    o("### 7.2 Area and timing (standalone, DC 3.3 ns ss) [S]\n")
    o("| | QC | TERNARY | INT8 |\n|---|---|---|---|")
    o("| array (u_array) kGE, Kb = 2 | " + " | ".join(f(S[v]["arr"] / S[v]["nand"] / 1000, 1) for v in V) + " |")
    o("| array kGE, Kb = 1 (section 2) | " + " | ".join(f(S1[v]["arr"] / S1[v]["nand"] / 1000, 1) for v in V) + " |")
    o("| Kb = 2 / Kb = 1 array area | " + " | ".join(f(S[v]["arr"] / S1[v]["arr"], 2) + "x" for v in V) + " |")
    o("| one PE (mean of 64) kGE | " + " | ".join(f(S[v]["pe"] / S[v]["nand"] / 1000, 2) for v in V) + " |")
    o("| array mm2 | " + " | ".join(f(S[v]["arr"] / 1e6, 3) for v in V) + " |")
    o("| input pipeline registers (x + weights + control) kGE | " + " | ".join(f(S[v]["wrap"] / S[v]["nand"] / 1000, 1) for v in V) + " |")
    o("| array vs QC | " + " | ".join(f(S[v]["arr"] / S["qc"]["arr"], 2) + "x" for v in V) + " |")
    for c in ("ss", "tt", "ff"):
        o(f"| fmax {c} MHz (WNS ns) | " + " | ".join(f"{S[v]['tim'][c]['fmax']:.1f} ({S[v]['tim'][c]['wns']:+.3f})" for v in V) + " |")
    o("\nWorst ss paths: " + "; ".join(f"{NAME[v]} `{S[v]['tim']['ss']['path']}`" for v in V) + ".  v3 in-chip QC array: "
      f"{w3['area']['pe_array'][0] / 1e6:.3f} mm2 (509.0 kGE).\n")
    o("### 7.3 Bit-exact check and energy (GLS tt SDF 2.5 ns, PT PX tt) [M] [P]\n")
    o("| point | weights | RTL (Verilator) | GLS SDF: rows checked / bad, timing violations | array mW | array pJ / block-op "
      "| pJ / dense-eq. MAC | + weight-input reg delta pJ / block-op | per block-op: PE regs + clock / PE datapath / "
      "shadow chain + array glue pJ |" + (" zero-delay GLS: array mW, SDF / zd |" if zd else ""))
    o("|---|---|---|---|---|---|---|---|---|" + ("---|" if zd else ""))
    for v in V:
        for pt in PTS[v]:
            g, p, e = G[pt], P[pt], E[pt]
            r = re.search(rf"rtl {pt} QAB_RESULT (\w+)", rtl).group(1)
            wt = {"qc": "s8kd QC", "tern": "s8kd expanded", "int8": "dense_s0 int8", "int8c": "s8kd as int8"}[pt.split("_")[0]]
            o(f"| {pt} | {wt} | {r} | {g['ok']}: {g['rows']} / {g['bad']}, {g['tviol']} | {p['arr'][3] * 1e3:.2f} | "
              f"{e['arr']:.2f} | {e['arr'] / 64:.4f} | {e['wd']:+.2f} | {e['regs']:.2f} / {e['dp']:.2f} / {e['chain']:.2f} |"
              + (f" {Z[pt]['arr'][3] * 1e3:.2f}, {p['arr'][3] / Z[pt]['arr'][3]:.2f} |" if zd else ""))
    o("\nblock-op = one 8x8 block (64 MACs) on one PE; a Kb = 2 PE does two per cycle, so energy / block-op = P x 2.5 ns "
      "/ 64 / 2 (1152 busy cycles per point).  Datapath = rotators + fused sum (QC), the fused u_acc (TERNARY / INT8); "
      "regs + clock = accumulator / shadow registers, their clock gates and clock pins.\n")
    for l in ("L2", "L4"):
        o(f"- {l}: array energy vs QC: TERNARY {E['tern_' + l]['arr'] / E['qc_' + l]['arr']:.2f}x (Kb = 1: "
          f"{E1['tern_' + l]['arr'] / E1['qc_' + l]['arr']:.2f}x), INT8 (dense_s0) {E['int8_' + l]['arr'] / E['qc_' + l]['arr']:.2f}x "
          f"({E1['int8_' + l]['arr'] / E1['qc_' + l]['arr']:.2f}x), INT8c (s8kd) {E['int8c_' + l]['arr'] / E['qc_' + l]['arr']:.2f}x "
          f"({E1['int8c_' + l]['arr'] / E1['qc_' + l]['arr']:.2f}x)")
    # ---- Kb = 1 vs Kb = 2 decomposition (mechanism)
    o("\n**Kb = 1 -> Kb = 2 per block-op (mean of L2 / L4, pJ) [P]:**\n")
    o("| variant | Kb | array | PE regs + clock | PE datapath | shadow chain + glue | w-reg delta |\n|---|---|---|---|---|---|---|")
    for v in V + ["int8c"]:
        for kb, EE in ((1, E1), (2, E)):
            o(f"| {NAME.get(v, 'INT8c')} | {kb} | {mean(EE, v, 'arr'):.2f} | {mean(EE, v, 'regs'):.2f} | {mean(EE, v, 'dp'):.2f} | "
              f"{mean(EE, v, 'chain'):.2f} | {mean(EE, v, 'wd'):+.2f} |")
    # ---- system model
    e_blk = {v: mean(E, v, "arr") + mean(E, v, "wd") for v in V}
    leak = {v: mean(E, v, "leak") for v in V}
    T_inf = CYC * T_CLK
    idle = CYC - steps
    E_rest = (w3["p_dat"] - w3["p_arr"] - w3["p_w"]) * T_inf * 1e6
    E_arr = {v: (bops * e_blk[v] * 1e-12 + idle * T_CLK * leak[v]) * 1e6 for v in V}
    Mbits = 4096 * 80
    e_bit = w3["e_read"] / 80
    a_bit = w3["area"]["weight SRAM"][1] / w3["nw"] / Mbits
    l_bit = w3["wleak"] / Mbits
    E_wrd = {v: steps * 8 * WB[v] * e_bit * 1e-6 for v in V}
    E_wrd["sp28"] = steps * 8 * 2 * 64 * e_bit * 1e-6
    E_wlk = {v: bits[v] * l_bit * T_inf * 1e6 for v in V + ["sp28"]}
    E_i = {v: E_rest + E_arr[v] + E_wrd[v] + E_wlk[v] for v in V}
    E_w3 = w3["p_w"] * T_inf * 1e6
    E_ii = {(v, e): E_rest + E_arr[v] + bits[v] * e * 1e-6 + (E_w3 if v == "qc" else 0.0) for v in V for e in (20, 70)}
    A = w3["area"]
    A_rest = (A["total"] - A["pe_array"][0] - A["weight SRAM"][0]) / 1e6
    A_arr = {v: (S[v]["arr"] + S[v]["wrap"] - S["qc"]["wrap"]) / 1e6 for v in V}
    A_w = {v: bits[v] * a_bit / 1e6 for v in V + ["sp28"]}
    A_i = {v: A_rest + A_arr[v] + A_w[v] for v in V}
    A_ii = {v: A_rest + A_arr[v] + (A["weight SRAM"][0] / 1e6 if v == "qc" else 0.0) for v in V}
    fr = {v: min(400.0, S[v]["tim"]["tt"]["fmax"]) for v in V}
    ips = {v: fr[v] * 1e6 / CYC for v in V}
    E_qc_meas = w3["p_arr"] * T_inf * 1e6
    E_cal = {v: E_qc_meas * E_arr[v] / E_arr["qc"] for v in V}
    o("\n### 7.4 System-level ablation per inference at 400 MHz, v3 (MODEL) [Mo]\n")
    o("Assumptions (all MODELLED unless marked measured), as section 4 with the v3 numbers:")
    o(f"- B1 (measured [P] + [Mo] macros, v3 `results/power_v3`, SDF SAIF image 0, +dat): everything except the PE array and "
      f"the weight macros = {(w3['p_dat'] - w3['p_arr'] - w3['p_w']) * 1e3:.2f} mW x {T_inf * 1e6:.1f} us = **{E_rest:.2f} uJ**; "
      f"kept for all variants (same v3 schedule: {CYC} cycles, {steps} array steps = {bops} block-op slots / inference; "
      "the stem's odd blocks are zero words, counted as block-ops here).")
    o(f"- B2: array = measured pJ / block-op (mean of L2 and L4, incl. the weight-input register delta) x {bops} "
      f"block-ops + array leakage during the {idle} non-array-step cycles.  Check on QC: model {E_arr['qc']:.2f} uJ vs "
      f"the in-chip measured v3 u_array {E_qc_meas:.2f} uJ.")
    o(f"- B3 (scenario i, on-chip weight SRAM): qa_wgt_4096x80m8 per-bit model of section 4 ({e_bit:.4f} pJ / bit read, "
      f"{a_bit:.4f} um2 / bit, {l_bit * 1e9:.3f} nW / bit), capacity = the weight bits, read every array step: "
      f"{8 * WB['qc']} / {8 * WB['tern']} / {8 * WB['int8']} b / step (two blocks per column).  Check on QC: "
      f"{E_wrd['qc']:.2f} uJ vs the v3 datatable 4.71 uJ.")
    o(f"- B4 (scenario ii, off-chip DRAM): every weight bit read once per inference at 20 / 70 pJ / bit; QC keeps the v3 "
      f"weight macros ({E_w3:.2f} uJ incl. leakage, measured [P] + [Mo]); TERNARY / INT8 no on-chip weight buffer (lower bound).")
    o(f"- B5: area = v3 layout minus its PE array and weight SRAM ({A_rest:.3f} mm2) + the variant's array (+ extra "
      f"weight-input register area vs QC) + the weight memory of B3 (scenario i) or none / the v3 QC weight macros "
      f"(scenario ii).  Throughput = min(400 MHz, tt fmax) / {CYC} cycles.")
    o("- B6 (storage row only): 2:8-sparse ternary weights stored at 64 b per 8x8 block (1 b / weight) vs 10 b per block "
      "for QC codes and 128 b for dense 2-b trits; no PE is modelled for it (its compute would need a sparse-ternary "
      "PE), only weight SRAM read (1024 b / step), leakage, area and DRAM.\n")
    o("| per inference | QC | TERNARY | INT8 |\n|---|---|---|---|")
    o("| array pJ / block-op (incl. w-reg delta), mean L2 / L4 [P] | " + " | ".join(f(e_blk[v], 2) for v in V) + " |")
    o("| B1 rest uJ | " + " | ".join(f(E_rest) for v in V) + " |")
    o("| B2 array uJ | " + " | ".join(f(E_arr[v]) for v in V) + " |")
    if zd:
        ez = {v: mean(E, v, "zarr") + mean(E, v, "zwd") for v in V}
        Ez = {v: (bops * ez[v] * 1e-12 + idle * T_CLK * leak[v]) * 1e6 for v in V}
        o("| B2z array uJ from the zero-delay GLS (no glitches; lower bound) | " + " | ".join(f(Ez[v]) for v in V) + " |")
    o("| B2' array uJ, calibrated to the v3 in-chip u_array (sensitivity) | " + " | ".join(f(E_cal[v]) for v in V) + " |")
    o("| (i) weight SRAM read uJ | " + " | ".join(f(E_wrd[v]) for v in V) + " |")
    o("| (i) weight SRAM leakage uJ | " + " | ".join(f(E_wlk[v]) for v in V) + " |")
    o("| **(i) on-chip system total uJ / inference** | " + " | ".join(f"**{E_i[v]:.1f}**" for v in V) + " |")
    o("| (i) total with B2' uJ | " + " | ".join(f(E_i[v] - E_arr[v] + E_cal[v], 1) for v in V) + " |")
    if zd:
        o("| (i) total with B2z uJ | " + " | ".join(f(E_i[v] - E_arr[v] + Ez[v], 1) for v in V) + " |")
    o("| (i) vs QC | " + " | ".join(f(E_i[v] / E_i["qc"], 2) + "x" for v in V) + " |")
    for e in (20, 70):
        o(f"| (ii) DRAM {e} pJ / b: DRAM uJ | " + " | ".join(f(bits[v] * e * 1e-6, 1) for v in V) + " |")
        o(f"| **(ii) {e} pJ / b total uJ** (dense: lower bound) | " + " | ".join(f"**{E_ii[(v, e)]:.1f}**" for v in V) + " |")
    o("| **(i) area mm2** (array / weight SRAM / total) | " + " | ".join(f"{A_arr[v]:.3f} / {A_w[v]:.2f} / **{A_i[v]:.2f}**" for v in V) + " |")
    o("| (ii) area mm2 (dense: no weight buffer, lower bound) | " + " | ".join(f(A_ii[v]) for v in V) + " |")
    o("| inferences / s (tt, <= 400 MHz) | " + " | ".join(f"{ips[v]:.0f}" for v in V) + " |")
    o("| **(i) inferences / s / mm2** | " + " | ".join(f"**{ips[v] / A_i[v]:.1f}**" for v in V) + " |")
    o("| (ii) inferences / s / mm2 | " + " | ".join(f(ips[v] / A_ii[v], 1) for v in V) + " |")
    # Kb = 1 totals for comparison (section 4 values, read back from this file)
    o("\n**Weight storage only (B3 / B4 / B6) [Mo]:**\n")
    o("| per inference | QC codes (10 b / block) | 2:8-sparse ternary (64 b / block) | dense ternary (128 b / block) | INT8 (512 b / block) |")
    o("|---|---|---|---|---|")
    SV = ["qc", "sp28", "tern", "int8"]
    o("| weight capacity MB | " + " | ".join(f(bits[v] / 8e6, 3) for v in SV) + " |")
    o("| vs QC | " + " | ".join(f(bits[v] / bits["qc"], 2) + "x" for v in SV) + " |")
    o("| (i) SRAM read + leakage uJ | " + " | ".join(f(E_wrd[v] + E_wlk[v]) for v in SV) + " |")
    o("| (i) SRAM area mm2 | " + " | ".join(f(A_w[v]) for v in SV) + " |")
    for e in (20, 70):
        o(f"| (ii) DRAM {e} pJ / b uJ | " + " | ".join(f(bits[v] * e * 1e-6, 1) for v in SV) + " |")
    o("\n### 7.5 Attribution (Kb = 2) [Mo]\n")
    dc1, dc2 = E_arr["int8"] - E_arr["tern"], E_arr["tern"] - E_arr["qc"]
    dw1 = E_wrd["int8"] + E_wlk["int8"] - E_wrd["tern"] - E_wlk["tern"]
    dw2 = E_wrd["tern"] + E_wlk["tern"] - E_wrd["qc"] - E_wlk["qc"]
    tot = E_i["int8"] - E_i["qc"]
    o(f"Scenario (i), INT8 -> QC saves {tot:.1f} uJ / inference ({E_i['int8'] / E_i['qc']:.2f}x):")
    o(f"- compute, INT8 -> TERNARY PE: array {E_arr['int8'] / E_arr['tern']:.2f}x, {dc1:.1f} uJ ({100 * dc1 / tot:.1f} %)")
    ec = {v: mean(E, v, "arr") + mean(E, v, "wd") for v in ("int8c", "tern", "int8")}
    o(f"  - of which arithmetic on identical operands (INT8c / TERNARY) {ec['int8c'] / ec['tern']:.2f}x and dense weight "
      f"statistics (INT8 / INT8c) {ec['int8'] / ec['int8c']:.2f}x (array + w-reg pJ / block-op, mean L2 / L4)")
    o(f"- compute, TERNARY -> QC PE: array {E_arr['tern'] / E_arr['qc']:.2f}x, {dc2:.1f} uJ ({100 * dc2 / tot:.1f} %)")
    o(f"- weight storage / traffic, int8 -> 2-b trits: weight SRAM {(E_wrd['int8'] + E_wlk['int8']) / (E_wrd['tern'] + E_wlk['tern']):.2f}x, "
      f"{dw1:.1f} uJ ({100 * dw1 / tot:.1f} %)")
    o(f"- weight storage / traffic, trits -> QC codes: weight SRAM {(E_wrd['tern'] + E_wlk['tern']) / (E_wrd['qc'] + E_wlk['qc']):.2f}x, "
      f"{dw2:.1f} uJ ({100 * dw2 / tot:.1f} %)")
    dsp = E_wrd["sp28"] + E_wlk["sp28"] - E_wrd["qc"] - E_wlk["qc"]
    o(f"- storage only, 2:8-sparse ternary -> QC codes: weight SRAM {(E_wrd['sp28'] + E_wlk['sp28']) / (E_wrd['qc'] + E_wlk['qc']):.2f}x, "
      f"{dsp:.1f} uJ; DRAM {bits['sp28'] / bits['qc']:.1f}x the bits ({(bits['sp28'] - bits['qc']) * 20e-6:.1f} / "
      f"{(bits['sp28'] - bits['qc']) * 70e-6:.1f} uJ more at 20 / 70 pJ / b)")
    for e in (20, 70):
        t2 = E_ii[("int8", e)] - E_ii[("qc", e)]
        dd = bits["int8"] * e * 1e-6 - bits["qc"] * e * 1e-6 - E_w3
        o(f"- scenario (ii) {e} pJ / b: INT8 -> QC saves >= {t2:.1f} uJ ({E_ii[('int8', e)] / E_ii[('qc', e)]:.2f}x), "
          f"of which compute {dc1 + dc2:.1f} uJ ({100 * (dc1 + dc2) / t2:.1f} %) and weight traffic {dd:.1f} uJ "
          f"({100 * dd / t2:.1f} %); TERNARY -> QC >= {E_ii[('tern', e)] - E_ii[('qc', e)]:.1f} uJ")
    o("\nKey numbers (Kb = 2):\n")
    o("| | QC | TERNARY | INT8 |\n|---|---|---|---|")
    o("| array kGE [S] | " + " | ".join(f(S[v]["arr"] / S[v]["nand"] / 1000, 1) for v in V) + " |")
    o("| pJ / block-op (array + w-reg, mean L2 / L4) [P] | " + " | ".join(f(e_blk[v]) for v in V) + " |")
    o("| on-chip system uJ / inference (i) [Mo] | " + " | ".join(f(E_i[v], 1) for v in V) + " |")
    o("| mm2 (i) [Mo] | " + " | ".join(f(A_i[v]) for v in V) + " |")
    o("| inferences / s / mm2 (i) [Mo] | " + " | ".join(f(ips[v] / A_i[v], 1) for v in V) + " |")
    o("| DRAM uJ at 20 / 70 pJ / b [Mo] | " + " | ".join(f"{bits[v] * 20e-6:.1f} / {bits[v] * 70e-6:.1f}" for v in V) + " |")
    # values for the mechanism text (filled by hand in MECH below, numbers computed here)
    m = {v: {k: (mean(E1, v, k), mean(E, v, k)) for k in ("arr", "regs", "dp", "chain", "wd")} for v in V + ["int8c"]}
    o("\n### 7.6 Why the QC-vs-TERNARY compute gap changes from Kb = 1 to Kb = 2\n")
    from .operand_toggles import report as toggles
    for line in MECH(m, E1, E, toggles(os.path.join(L, "vec"))):
        o(line)
    o("\n### 7.7 Caveats (Kb = 2)\n")
    o("- As section 6 (pre-CTS, WLM, ideal clock, tt 25 C; activity of two passes of image 0; no operand isolation / "
      "zero skipping).  The B1 rest is the v3 chip's own (measured), so the Kb = 2 totals are not comparable 1:1 with the "
      "Kb = 1 totals of section 4 (v2 rest, 159 982 cycles), only variant-to-variant.")
    o("- The TERNARY / INT8 PEs got the same fused-sum treatment as the v3 QC PE (one adder tree incl. the accumulator); "
      "at Kb = 1 all three PEs had a separate block sum and accumulate adder.  Kb = 1 -> Kb = 2 therefore changes both "
      "the block count per cycle and the adder structure, for all three variants alike.")
    o("- Weight memory: linear per-bit model of the 4096x80 macro (section 6); the 2:8-sparse ternary row is storage / "
      "DRAM only (no sparse PE, no index-decode logic).")
    o("- fmax: one synthesis at 3.3 ns per variant, no 2.0 ns probe at Kb = 2.")
    sec = "\n".join(out) + "\n"
    fn = os.path.join(R, "ablation.md")
    old = open(fn).read()
    if MARK in old:
        old = old[:old.index(MARK)]
    hdr = ("Sections 1-6: Kb = 1 (v2 array, one block per PE per cycle).  Section 7: Kb = 2 (v3 array, two blocks per "
           "PE per cycle; `report3.py`).\n")
    if hdr not in old:
        old = old.replace("\n## 1. Variants", "\n" + hdr + "\n## 1. Variants", 1)
    open(fn, "w").write(old.rstrip("\n") + "\n\n" + sec)
    D = os.path.join(R, "ablation_kb2")
    shutil.rmtree(D, ignore_errors=True)
    os.makedirs(D)
    for v in V:
        for p in glob.glob(os.path.join(L, "out", v, "*.txt")):
            b = os.path.basename(p)
            if b.endswith("_cells.txt"):
                open(os.path.join(D, b), "w").writelines(x for x in open(p) if "clk_gate" not in x)
            elif b.startswith(("power_", "gls_", "sdf_")):
                shutil.copy(p, os.path.join(D, b))
    for p in glob.glob(os.path.join(L, "out", "*", "qab3_*_w*", "*.txt")):
        shutil.copy(p, os.path.join(D, os.path.basename(os.path.dirname(p)) + "_" + os.path.basename(p)))
    shutil.copy(os.path.join(L, "vec", "stats.txt"), os.path.join(D, "vec_stats.txt"))
    shutil.copy(os.path.join(L, "rtl.txt"), os.path.join(D, "rtl.txt"))
    print(sec)


def syn_dir(d, prefix=None):
    """syn() on a host summary dir (files summary.txt, ...) or on the flat results copy (prefix + file)."""
    if prefix is None:
        tmp = {b: os.path.join(d, b + ".txt") for b in ("summary", "area_hier", "pt_ss", "pt_tt", "pt_ff")}
        return syn_files(tmp)
    return syn_files({b: os.path.join(d, prefix + b + ".txt") for b in ("summary", "area_hier", "pt_ss", "pt_tt", "pt_ff")})


def syn_files(F):
    s = open(F["summary"]).read()
    area, kge = (float(re.search(p, s).group(1)) for p in (r"cell_area_um2 (\S+)", r"gate_eq_kGE (\S+)"))
    nand = area / kge / 1000.0
    rows = {}
    for line in open(F["area_hier"]):
        t = line.split()
        try:
            rows[t[0]] = float(t[1])
        except (ValueError, IndexError):
            continue
    arr = [k for k in rows if k.endswith("u_array")]
    assert len(arr) == 1, arr
    arr = arr[0]
    pes = [rows[k] for k in rows if k.startswith(arr + "/") and k.endswith("u_pe")]
    assert len(pes) == 64, len(pes)
    tim = {}
    for c in ("ss", "tt", "ff"):
        m = re.search(r"clock qa_clk period_ns (\S+) wns_ns (\S+) fmax_mhz (\S+) path (\S+) -> (\S+)", open(F["pt_" + c]).read())
        tim[c] = dict(wns=float(m.group(2)), fmax=float(m.group(3)), path=f"{m.group(4)} -> {m.group(5)}")
    return dict(nand=nand, total=area, arr=rows[arr], pe=sum(pes) / 64, wrap=area - rows[arr], tim=tim)


def MECH(m, E1, E, tg):
    """Mechanism text: per-block-op split Kb = 1 -> Kb = 2 (section 7.3 numbers) and the operand toggles (tg)."""
    q, t = m["qc"], m["tern"]
    r = {kb: (mean(EE, "tern", "arr") + mean(EE, "tern", "wd")) / mean(EE, "qc", "arr") for kb, EE in ((1, E1), (2, E))}
    rl = {(kb, l): E_[f"tern_{l}"]["arr"] / E_[f"qc_{l}"]["arr"] for kb, E_ in ((1, E1), (2, E)) for l in ("L2", "L4")}
    d = {(v, kb, l): EE[f"{v}_{l}"]["dp"] for v in ("qc", "tern") for kb, EE in ((1, E1), (2, E)) for l in ("L2", "L4")}
    g = {(v, kb, l): EE[f"{v}_{l}"]["regs"] for v in ("qc", "tern") for kb, EE in ((1, E1), (2, E)) for l in ("L2", "L4")}
    return [
        f"TERNARY / QC array energy per block-op (incl. the weight-register delta, mean L2 / L4): Kb = 1 {r[1]:.2f}x, "
        f"Kb = 2 {r[2]:.2f}x.  The mean barely moves, but per layer it does: L2 {rl[(1, 'L2')]:.2f}x -> "
        f"{rl[(2, 'L2')]:.2f}x (gap widens), L4 {rl[(1, 'L4')]:.2f}x -> {rl[(2, 'L4')]:.2f}x (TERNARY becomes cheaper "
        "than QC).  Three mechanisms, measured on the PE split of 7.3 (pJ per block-op) and on the operand toggles of "
        "the streams (`operand_toggles.py`, per PE-cycle = 2 blocks):",
        f"1. **Registers + clock amortise over Kb, equally for both.**  One set of 8 accumulators + 8 shadow registers "
        f"and their clock gates serves Kb blocks per cycle: QC {g[('qc', 1, 'L2')]:.2f} / {g[('qc', 1, 'L4')]:.2f} -> "
        f"{g[('qc', 2, 'L2')]:.2f} / {g[('qc', 2, 'L4')]:.2f}, TERNARY {g[('tern', 1, 'L2')]:.2f} / {g[('tern', 1, 'L4')]:.2f} "
        f"-> {g[('tern', 2, 'L2')]:.2f} / {g[('tern', 2, 'L4')]:.2f} pJ (L2 / L4).  Being the same for QC and TERNARY "
        "(20- vs 21-b accumulators), this part never contributes to the gap; halving it makes the datapath difference a "
        "larger share of the total, which by itself widens the ratio.",
        f"2. **The datapath per block gets cheaper with the fused Kb = 2 sum for both** (one carry-save tree incl. the "
        f"accumulator, one carry-propagate add per 2 blocks instead of a block add + a 20-b accumulate add per block): "
        f"L2 datapath QC {d[('qc', 1, 'L2')]:.2f} -> {d[('qc', 2, 'L2')]:.2f}, TERNARY {d[('tern', 1, 'L2')]:.2f} -> "
        f"{d[('tern', 2, 'L2')]:.2f} pJ.  QC saves more per block (x{d[('qc', 1, 'L2')] / d[('qc', 2, 'L2')]:.2f} vs "
        f"x{d[('tern', 1, 'L2')] / d[('tern', 2, 'L2')]:.2f}): its per-block work is 2 operands per lane, so the "
        "carry-propagate adds it sheds are a large part of it; a ternary block brings 8 operands per lane and its "
        "compressor tree, which does not shrink, dominates.  With items 1 and 2 the L2 gap widens.",
        f"3. **The v3 QC negate encoding toggles with the weight sign, independent of the data.**  qa_pe_acc4 forms a "
        "negative term as (x XOR 1...1) + carry-in, so a 20-b operand flips all its bits whenever the sign of its trit "
        "changes from one step to the next, even for x = 0; the v2 QC PE (and the TERNARY PEs) use the value form "
        "(+x / -x / 0), which stays 0 for x = 0.  Operand toggles per PE-cycle, QC XOR form / QC value form / TERNARY "
        f"values: L2 {tg['L2']['qx']:.0f} / {tg['L2']['qv']:.0f} / {tg['L2']['tv']:.0f}, L4 {tg['L4']['qx']:.0f} / "
        f"{tg['L4']['qv']:.0f} / {tg['L4']['tv']:.0f} (x lanes zero: L2 {100 * tg['L2']['xz']:.0f} %, L4 "
        f"{100 * tg['L4']['xz']:.0f} %; {100 * tg['L4']['neg']:.0f} % of the L4 terms are negative).  On the zero-heavy "
        f"L4 stream the QC datapath therefore costs MORE per block at Kb = 2 than at Kb = 1 ({d[('qc', 1, 'L4')]:.2f} -> "
        f"{d[('qc', 2, 'L4')]:.2f} pJ; the zero-delay runs show the same, so it is functional toggling, not glitches), "
        f"while TERNARY drops ({d[('tern', 1, 'L4')]:.2f} -> {d[('tern', 2, 'L4')]:.2f}): the L4 gap inverts.",
        "Net: the PE-level QC-vs-TERNARY compute gap stays small at Kb = 2 (about the Kb = 1 value on the mean of the two "
        "layers) because items 1-2 (widening) and item 3 (a QC-specific, data-independent cost that grows with the "
        "zero share) cancel on these two passes.  A value-form negate (or gating the XOR with e AND x != 0) in qa_pe_acc4 "
        "would remove item 3 (not evaluated here).  The system-level QC advantage remains weight storage / traffic "
        "(7.5): 160 vs 2048 b per array step.",
    ]


if __name__ == "__main__":
    main()
