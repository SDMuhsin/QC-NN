"""QC18-ACC array ablation report:  python3 -m qc18acc.ablation.report <L> <results_dir>

L = local ablation dir (run.sh: vec/stats.txt, rtl.txt, out/<v>/ = the hosts' summaries).  Writes
<results_dir>/ablation.md and copies the summaries (design names only) to <results_dir>/ablation/.
Measured: array area / fmax (DC + PT), GLS check, PT PX power of the PE busy window.  The system section is a
MODEL (every assumption labelled in the output) built on the measured v2 numbers of results/power_v2.md.
"""
import glob
import os
import re
import shutil
import sys

V = ["qc", "tern", "int8"]
NAME = {"qc": "QC", "tern": "TERNARY", "int8": "INT8"}
WB = {"qc": 10, "tern": 128, "int8": 512}          # weight bits per column per cycle
ACC = {"qc": 20, "tern": 21, "int8": 32}
PTS = {"qc": ["qc_L2", "qc_L4"], "tern": ["tern_L2", "tern_L4"], "int8": ["int8_L2", "int8_L4", "int8c_L2", "int8c_L4"]}
LAY = {"L2": "blocks.3.c1 (layer 2, K = 144, 16 tiles)", "L4": "blocks.7.c1 (layer 4, K = 576, 4 tiles)"}
T_CLK = 2.5e-9                                     # GLS / PT clock (400 MHz)
CYC = 159982                                       # v2 START..DONE cycles / inference (results/power_v2.md)
HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.join(HERE, "..", "results", "power_v2")
V2A = os.path.join(HERE, "..", "impl", "results", "qa2_w3.3", "area.txt")


def f(x, n=2):
    return f"{x:.{n}f}"


def probe(L, v, per="2.0"):
    """fmax probe: the same RTL synthesized at a tighter target (QAB_PERIOD=2.0 remote.sh syn <v>), any host."""
    d = glob.glob(os.path.join(L, "out", "*", f"qab_{v}_w{per}"))
    if not d:
        return None
    r = {}
    for c in ("ss", "tt"):
        m = re.search(r"wns_ns (\S+) fmax_mhz (\S+)", open(os.path.join(d[0], f"pt_{c}.txt")).read())
        r[c] = (float(m.group(1)), float(m.group(2)))
    s = open(os.path.join(d[0], "summary.txt")).read()
    r["kge"] = float(re.search(r"gate_eq_kGE (\S+)", s).group(1))
    return r


def syn(L, v):
    d = os.path.join(L, "out", v, f"qab_{v}_w3.3")
    s = open(os.path.join(d, "summary.txt")).read()
    area, kge = (float(re.search(p, s).group(1)) for p in (r"cell_area_um2 (\S+)", r"gate_eq_kGE (\S+)"))
    nand = area / kge / 1000.0
    rows = {}
    for line in open(os.path.join(d, "area_hier.txt")):
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
        m = re.search(r"clock qa_clk period_ns (\S+) wns_ns (\S+) fmax_mhz (\S+) path (\S+) -> (\S+)",
                      open(os.path.join(d, f"pt_{c}.txt")).read())
        tim[c] = dict(wns=float(m.group(2)), fmax=float(m.group(3)), path=f"{m.group(4)} -> {m.group(5)}")
    return dict(nand=nand, total=area, arr=rows[arr], pe=sum(pes) / 64, wrap=area - rows[arr], tim=tim, arr_name=arr)


def gls(L, v, pt):
    t = open(os.path.join(L, "out", v, f"gls_{pt}.txt")).read()
    m = re.search(r"QAB_RESULT (\w+) tiles (\d+) rows_checked (\d+) bad (\d+) steps (\d+)", t)
    tv = int(re.search(r"timing_violations (\d+)", t).group(1))
    return dict(ok=m.group(1), rows=int(m.group(3)), bad=int(m.group(4)), steps=int(m.group(5)), tviol=tv)


def power(L, v, pt, x=""):
    rows = {}
    fn = os.path.join(L, "out", v, f"power{x}_{pt}_cells.txt")
    if x and not os.path.exists(fn):
        return None
    for line in open(fn):
        if line.startswith("#"):
            continue
        t = line.split()
        rows[t[0]] = [float(x) for x in t[2:6]]
    arr = [k for k in rows if k.endswith("u_array")][0]
    pe = [k for k in rows if k.startswith(arr + "/") and k.endswith("u_pe")]
    sub = {}
    for k in rows:
        last = k.rsplit("/", 1)[-1]
        n = [x for x in ("u_rot1", "u_rot2", "u_tadd", "u_acc", "u_dot") if last.endswith(x)]
        if k.startswith(arr + "/") and n and "u_pe" in k.rsplit("/", 2)[-2] + k.rsplit("/", 1)[0]:
            sub[n[0]] = [a + b for a, b in zip(sub.get(n[0], [0.0] * 4), rows[k])]
    pet = [sum(rows[k][i] for k in pe) for i in range(4)]
    txt = open(os.path.join(L, "out", v, f"power{x}_{pt}.txt")).read()
    grp = {g: float(re.search(rf"^{g}\s+\S+\s+\S+\s+\S+\s+(\S+)", txt, re.M).group(1))
           for g in ("clock_network", "register", "combinational")}
    return dict(arr=rows[arr], non=rows["NONARRAY_LEAF"], des=rows["DESIGN"], pe=pet, sub=sub, grp=grp)


def v2_numbers():
    blk = {}
    for line in open(os.path.join(V2, "sdf_2.5ns_blocks.txt")):
        if line.startswith("#"):
            continue
        t = line.split()
        blk[t[0]] = [float(x) for x in t[1:5]]
    dat = {}
    for line in open(os.path.join(V2, "sdf_2.5ns_macros.txt")):
        m = re.match(r"datmacro:(\S+) n (\d+) .*E_read (\S+) .* P_dyn (\S+) leak_dat (\S+)", line)
        if m:
            dat[m.group(1)] = dict(n=int(m.group(2)), e_read=float(m.group(3)), p_dyn=float(m.group(4)), leak=float(m.group(5)))
    macros = [k for k in blk if k.startswith("macro:")]
    p_dat = blk["design:qa_top"][3] - sum(blk[k][0] for k in macros) + sum(d["p_dyn"] for d in dat.values())
    wg = "qa_wgt_4096x80m8"
    p_w = blk["macro:" + wg][3] - blk["macro:" + wg][0] + dat[wg]["p_dyn"]
    p_arr = blk["hier:u_array"][3]
    area = {}
    for line in open(V2A):
        m = re.match(r"(pe_array|weight SRAM).*?\s(\d+)\s+(\d+)\s+(\d+)\s+\S+\s+\S+$", line)
        if m:
            area[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
        m = re.match(r"total_um2 (\d+)", line)
        if m:
            area["total"] = int(m.group(1))
    return dict(p_dat=p_dat, p_w=p_w, p_arr=p_arr, wleak=blk["macro:" + wg][2] / dat[wg]["n"],
                e_read=dat[wg]["e_read"], nw=dat[wg]["n"], area=area)


def main():
    L, R = sys.argv[1], sys.argv[2]
    st = open(os.path.join(L, "vec", "stats.txt")).read()
    sched = dict(re.findall(r"(\w+) (\d+)", st.splitlines()[0].replace("schedule ", "")))
    steps, bops = int(sched["array_steps"]), int(sched["block_ops"])
    bits = {"qc": int(sched["qc_bits"]), "tern": int(sched["tern_bits"]), "int8": int(sched["int8_bits"])}
    S = {v: syn(L, v) for v in V}
    G = {pt: gls(L, v, pt) for v in V for pt in PTS[v]}
    P = {pt: power(L, v, pt) for v in V for pt in PTS[v]}
    Z = {pt: power(L, v, pt, "_zd") for v in V for pt in PTS[v]}
    zd = all(Z.values())
    rtl = open(os.path.join(L, "rtl.txt")).read()
    w2 = v2_numbers()
    out = []
    o = out.append
    o("# QC18-ACC array ablation: QC vs TERNARY vs INT8 PE (same array, pipeline, dataflow)\n")
    o("Scripts: `qc18acc/ablation/` (README: qc18acc/README.md, \"Array ablation\").  Flow as `impl/` (DC W-2024.09, "
      "tcbn65gplus, WLM WireAreaLowkCon enclosed, 3.3 ns at ss, `impl/constraints.sdc`; PT ss / tt / ff pre-CTS), GLS "
      "VCS with the DC tt SDF (ideal clock, 0.5 ns input delay, timing checks on) at 2.5 ns, PT PX tt 1.0 V 25 C with "
      "the synthesis WLM over the SAIF of the PE busy window.  Summaries: `results/ablation/`.\n")
    o("## 1. Variants\n")
    o("| | QC (v2, unchanged) | TERNARY | INT8 |\n|---|---|---|---|")
    o("| PE RTL | `hw/rtl/qa_pe.sv` (2 rotators, trit + 2-term add, accumulate) | `ablation/rtl/qab_pe.sv` V=1: 8 trit-selects + 8-term adder tree per lane | V=2: 8 signed 8x8 multipliers + adder tree per lane |")
    o("| weight bits / block (per PE / column) | 10 | 128 (64 trits x 2 b) | 512 (64 x int8) |")
    o("| weight bits into the array / cycle | 80 | 1024 | 4096 |")
    o("| lane sum / accumulator | 10 b / 20 b | 12 b / 21 b | 19 b / 32 b |")
    o("\nIdentical in all three: 8 x 8 PEs (rows = 8 output pixels, columns = 8 output-channel groups of 8), one 8x8 "
      "block per PE per cycle, output-stationary accumulators (first step overwrites), capture into the shadow "
      "register on the last step, shadow chain towards the column head, the input pipeline register (x 512 b, weights "
      "8 x WB b, vld / first / last / shift; `rtl/qab_top.sv`).  TERNARY accumulator: the worst case of an arbitrary "
      "ternary 3x3x512 conv is 4608 x 128 = 589 824 < 2^20, i.e. 21 b signed (QC: 2 x 576 x 127 < 2^18, v2 uses 20 b).\n")
    o("Stream (`vectors.py`): s8kd_s0 test image 0, the REAL v2 array inputs (golden model up to the pass, then "
      "`golden.gather_window`: v2 tap order kh, cb, kw, kw window, padding lanes zero), 2304 steps per point:")
    for l in ("L2", "L4"):
        line = [x for x in st.splitlines() if x.startswith(l + " ")][0]
        o(f"- {l} = {LAY[l]}: {line.split(' ', 2)[2]}")
    o("- weights: QC = the pass's v2 weight words; TERNARY = the same blocks expanded (same math); INT8 = dense_s0 "
      "(`/tmp/root/qc18/final/dense_s0/best.pt`) conv of the same layer, BN folded (`qc18.verify.fold`), symmetric "
      "per-output-channel int8; INT8c (control) = the s8kd blocks as int8 (same math as QC).\n")
    o("## 2. Area and timing (standalone, DC 3.3 ns ss)\n")
    o("| | QC | TERNARY | INT8 |\n|---|---|---|---|")
    o("| array (u_array) kGE | " + " | ".join(f(S[v]["arr"] / S[v]["nand"] / 1000, 1) for v in V) + " |")
    o("| one PE (mean of 64) kGE | " + " | ".join(f(S[v]["pe"] / S[v]["nand"] / 1000, 2) for v in V) + " |")
    o("| array mm2 | " + " | ".join(f(S[v]["arr"] / 1e6, 3) for v in V) + " |")
    o("| input pipeline registers (x + weights + control) kGE | " + " | ".join(f(S[v]["wrap"] / S[v]["nand"] / 1000, 1) for v in V) + " |")
    o("| array vs QC | " + " | ".join(f(S[v]["arr"] / S["qc"]["arr"], 2) + "x" for v in V) + " |")
    for c in ("ss", "tt", "ff"):
        o(f"| fmax {c} MHz (WNS ns) | " + " | ".join(f"{S[v]['tim'][c]['fmax']:.1f} ({S[v]['tim'][c]['wns']:+.3f})" for v in V) + " |")
    pr = {v: probe(L, v) for v in V}
    if all(pr.values()):
        o("| fmax probe: synthesized at 2.0 ns, ss / tt MHz (top kGE) | " + " | ".join(
            f"{pr[v]['ss'][1]:.1f} / {pr[v]['tt'][1]:.1f} ({pr[v]['kge']:.0f})" for v in V) + " |")
    o("\nAt the 3.3 ns target DC closes timing for every variant (INT8: ss WNS -6 ps, i.e. 302 MHz; DC sizes to the constraint), so the 3.3 ns fmax is "
      "the target, not a limit; the 2.0 ns probe (same flow, `QAB_PERIOD=2.0 remote.sh syn <v>`, area grows) shows "
      "the achievable ss / tt clock.")
    o("\nWorst ss paths: " + "; ".join(f"{NAME[v]} `{S[v]['tim']['ss']['path']}`" for v in V) + ".  v2 in-chip QC "
      f"array: {w2['area']['pe_array'][0] / 1e6:.3f} mm2 (396.4 kGE, 6.17 kGE / PE).\n")
    o("## 3. Bit-exact check and energy (GLS tt SDF 2.5 ns, PT PX tt)\n")
    o("| point | weights | RTL (Verilator) | GLS SDF: rows checked / bad, timing violations | array mW | array pJ / block-op | "
      "pJ / dense-eq. MAC | + weight-input reg delta pJ / block-op | PE: clock+regs / dot / acc uW |"
      + (" zero-delay GLS: array mW, SDF / zd |" if zd else ""))
    o("|---|---|---|---|---|---|---|---|---|" + ("---|" if zd else ""))
    E = {}
    for v in V:
        for pt in PTS[v]:
            g, p = G[pt], P[pt]
            l = pt.split("_")[1]
            q = P["qc_" + l]
            e_arr = p["arr"][3] * T_CLK / 64 * 1e12
            e_d = (p["non"][3] - q["non"][3]) * T_CLK / 64 * 1e12
            E[pt] = dict(arr=e_arr, wd=e_d, leak=p["arr"][2] + p["non"][2] - q["non"][2])
            r = re.search(rf"rtl {pt} QAB_RESULT (\w+)", rtl).group(1)
            pe = p["pe"][3] / 64 * 1e6
            dot = sum(x[3] for k, x in p["sub"].items() if k != "u_acc") / 64 * 1e6
            acc = p["sub"].get("u_acc", [0] * 4)[3] / 64 * 1e6
            wt = {"qc": "s8kd QC", "tern": "s8kd expanded", "int8": "dense_s0 int8", "int8c": "s8kd as int8"}[pt.split("_")[0]]
            o(f"| {pt} | {wt} | {r} | {g['ok']}: {g['rows']} / {g['bad']}, {g['tviol']} | {p['arr'][3] * 1e3:.2f} | "
              f"{e_arr:.2f} | {e_arr / 64:.4f} | {e_d:+.2f} | {pe - dot - acc:.0f} / {dot:.0f} / {acc:.0f} |"
              + (f" {Z[pt]['arr'][3] * 1e3:.2f}, {p['arr'][3] / Z[pt]['arr'][3]:.2f} |" if zd else ""))
            if zd:
                E[pt]["zarr"] = Z[pt]["arr"][3] * T_CLK / 64 * 1e12
                E[pt]["zwd"] = (Z[pt]["non"][3] - Z["qc_" + l]["non"][3]) * T_CLK / 64 * 1e12
    o("\nblock-op = one PE processing one 8x8 block (64 MACs) in one cycle; array power = PT u_array (64 PEs + shadow "
      "chains) over the 2304-cycle busy window, energy = P x 2.5 ns / 64.  Weight-input reg delta = PT power of the "
      "leaf cells outside u_array (input registers) minus the QC run's (the x stream is identical, so this is the "
      "wider weight register).  PE split: dot = rotators + trit / 2-term add (QC) or u_dot (TERNARY / INT8), acc = "
      "accumulate adder, rest = registers + clock gates.\n")
    for l in ("L2", "L4"):
        o(f"- {l}: array energy vs QC: TERNARY {E['tern_' + l]['arr'] / E['qc_' + l]['arr']:.2f}x, INT8 (dense_s0) "
          f"{E['int8_' + l]['arr'] / E['qc_' + l]['arr']:.2f}x, INT8c (s8kd) {E['int8c_' + l]['arr'] / E['qc_' + l]['arr']:.2f}x")
    # ---- system model
    e_blk = {v: sum(E[f"{v}_{l}"]["arr"] + E[f"{v}_{l}"]["wd"] for l in ("L2", "L4")) / 2 for v in V}
    leak = {v: sum(E[f"{v}_{l}"]["leak"] for l in ("L2", "L4")) / 2 for v in V}
    T_inf = CYC * T_CLK
    idle = CYC - steps
    E_rest = (w2["p_dat"] - w2["p_arr"] - w2["p_w"]) * T_inf * 1e6
    E_arr = {v: (bops * e_blk[v] * 1e-12 + idle * T_CLK * leak[v]) * 1e6 for v in V}
    Mbits = 4096 * 80
    e_bit = w2["e_read"] / 80
    a_bit = w2["area"]["weight SRAM"][1] / w2["nw"] / Mbits
    l_bit = w2["wleak"] / Mbits
    E_wrd = {v: steps * 8 * WB[v] * e_bit * 1e-6 for v in V}
    E_wlk = {v: bits[v] * l_bit * T_inf * 1e6 for v in V}
    E_i = {v: E_rest + E_arr[v] + E_wrd[v] + E_wlk[v] for v in V}
    E_w2 = w2["p_w"] * T_inf * 1e6
    E_ii = {(v, e): E_rest + E_arr[v] + bits[v] * e * 1e-6 + (E_w2 if v == "qc" else 0.0) for v in V for e in (20, 70)}
    A = w2["area"]
    A_rest = (A["total"] - A["pe_array"][0] - A["weight SRAM"][0]) / 1e6
    A_arr = {v: (S[v]["arr"] + S[v]["wrap"] - S["qc"]["wrap"]) / 1e6 for v in V}
    A_w = {v: bits[v] * a_bit / 1e6 for v in V}
    A_i = {v: A_rest + A_arr[v] + A_w[v] for v in V}
    A_ii = {v: A_rest + A_arr[v] + (A["weight SRAM"][0] / 1e6 if v == "qc" else 0.0) for v in V}
    fr = {v: min(400.0, S[v]["tim"]["tt"]["fmax"]) for v in V}
    ips = {v: fr[v] * 1e6 / CYC for v in V}
    E_qc_meas = w2["p_arr"] * T_inf * 1e6
    o("## 4. System-level ablation per inference at 400 MHz (MODEL)\n")
    o("Assumptions (all MODELLED unless marked measured):")
    o(f"- A1 (measured, v2 `results/power_v2.md`, SDF SAIF image 0, +dat): everything except the PE array and the weight "
      f"macros = {(w2['p_dat'] - w2['p_arr'] - w2['p_w']) * 1e3:.2f} mW x {T_inf * 1e6:.1f} us = **{E_rest:.2f} uJ** "
      f"(act macros, PPU, drain, head, AGU / xbar / seq / host, param + desc macros, wrappers, their leakage); kept for "
      f"all variants (same schedule: {CYC} cycles, {steps} array steps = {bops} block-ops / inference).")
    o(f"- A2: array = measured pJ / block-op (mean of L2 and L4, incl. the weight-input register delta) x {bops} "
      f"block-ops + array leakage (measured, PT) during the {idle} non-array-step cycles.  Check on QC: model "
      f"{E_arr['qc']:.2f} uJ vs the in-chip measured u_array {E_qc_meas:.2f} uJ (v2).")
    o(f"- A3 (scenario i, on-chip weight SRAM): built from qa_wgt_4096x80m8 (datatable tt, EMA 000; area incl. ring): "
      f"read {w2['e_read']:.2f} pJ / 80 b = **{e_bit:.4f} pJ / bit**, area {a_bit:.4f} um2 / bit, leakage "
      f"{w2['wleak'] * 1e3:.3f} mW / macro = {l_bit * 1e9:.3f} nW / bit (PT, tt 25 C); energy / area scale linearly with "
      f"bits (N copies of the macro; capacity = the weight bits exactly).  Weights read every array step as in v2: "
      f"{8 * WB['qc']} / {8 * WB['tern']} / {8 * WB['int8']} b / step.  Capacity: QC {bits['qc'] / 8e6:.3f} MB, "
      f"TERNARY {bits['tern'] / 8e6:.2f} MB, INT8 {bits['int8'] / 8e6:.2f} MB (conv weights; the 5 kB FC is in A1).")
    o("- A4 (scenario ii, off-chip DRAM): every weight bit read once per inference at 20 pJ / bit (Horowitz ISSCC 2014, "
      "DRAM I/O) or 70 pJ / bit (Malladi ISCA 2012, DDR3).  QC keeps its measured on-chip weight SRAM (v2 weight macros, "
      f"{E_w2:.2f} uJ, 6 macros) for the per-step re-reads; TERNARY / INT8 are charged NO on-chip weight buffer: "
      "**a lower bound for the dense variants** (each weight block is re-read by every pixel tile, so they need an "
      "on-chip buffer of the size in A3 or more DRAM traffic).")
    o(f"- A5: area = v2 layout minus its PE array and weight SRAM ({A_rest:.3f} mm2: act / param / desc macros, PPU, "
      f"drain, head, control) + the variant's measured array (+ its extra weight-input register area vs QC) + the "
      f"weight memory of A3 (scenario i) or none / the v2 QC weight macros (scenario ii).  Throughput = min(400 MHz, "
      f"tt fmax) / {CYC} cycles.\n")
    o("| per inference | QC | TERNARY | INT8 |\n|---|---|---|---|")
    o("| array pJ / block-op (incl. w-reg delta), mean L2 / L4 | " + " | ".join(f(e_blk[v], 2) for v in V) + " |")
    o("| A1 rest uJ | " + " | ".join(f(E_rest) for v in V) + " |")
    o("| A2 array uJ | " + " | ".join(f(E_arr[v]) for v in V) + " |")
    E_cal = {v: E_qc_meas * E_arr[v] / E_arr["qc"] for v in V}
    if zd:
        ez = {v: sum(E[f"{v}_{l}"]["zarr"] + E[f"{v}_{l}"]["zwd"] for l in ("L2", "L4")) / 2 for v in V}
        Ez = {v: (bops * ez[v] * 1e-12 + idle * T_CLK * leak[v]) * 1e6 for v in V}
        o("| A2z array uJ from the zero-delay GLS (no glitches; lower bound, sensitivity) | " + " | ".join(f(Ez[v]) for v in V) + " |")
    o("| A2' array uJ, calibrated: v2 in-chip u_array x A2(v) / A2(QC) (sensitivity) | " + " | ".join(f(E_cal[v]) for v in V) + " |")
    o("| (i) weight SRAM read uJ | " + " | ".join(f(E_wrd[v]) for v in V) + " |")
    o("| (i) weight SRAM leakage uJ | " + " | ".join(f(E_wlk[v]) for v in V) + " |")
    o("| **(i) total uJ / inference** | " + " | ".join(f"**{E_i[v]:.1f}**" for v in V) + " |")
    o("| (i) total with A2' uJ | " + " | ".join(f(E_i[v] - E_arr[v] + E_cal[v], 1) for v in V) + " |")
    if zd:
        o("| (i) total with A2z uJ | " + " | ".join(f(E_i[v] - E_arr[v] + Ez[v], 1) for v in V) + " |")
    o("| (i) vs QC | " + " | ".join(f(E_i[v] / E_i["qc"], 2) + "x" for v in V) + " |")
    for e in (20, 70):
        o(f"| (ii) DRAM {e} pJ / b: DRAM uJ | " + " | ".join(f(bits[v] * e * 1e-6, 1) for v in V) + " |")
        o(f"| **(ii) {e} pJ / b total uJ** (dense: lower bound) | " + " | ".join(f"**{E_ii[(v, e)]:.1f}**" for v in V) + " |")
    o("| (i) area mm2 (array / weight SRAM / total) | " + " | ".join(f"{A_arr[v]:.3f} / {A_w[v]:.2f} / {A_i[v]:.2f}" for v in V) + " |")
    o("| (ii) area mm2 (dense: no weight buffer, lower bound) | " + " | ".join(f(A_ii[v]) for v in V) + " |")
    o("| inferences / s (tt) | " + " | ".join(f"{ips[v]:.0f}" for v in V) + " |")
    o("| (i) inferences / s / mm2 | " + " | ".join(f(ips[v] / A_i[v], 1) for v in V) + " |")
    o("| (ii) inferences / s / mm2 | " + " | ".join(f(ips[v] / A_ii[v], 1) for v in V) + " |")
    o("\n## 5. Attribution\n")
    dc1, dc2 = E_arr["int8"] - E_arr["tern"], E_arr["tern"] - E_arr["qc"]
    dw1 = E_wrd["int8"] + E_wlk["int8"] - E_wrd["tern"] - E_wlk["tern"]
    dw2 = E_wrd["tern"] + E_wlk["tern"] - E_wrd["qc"] - E_wlk["qc"]
    tot = E_i["int8"] - E_i["qc"]
    o(f"Scenario (i), INT8 -> QC saves {tot:.1f} uJ / inference ({E_i['int8'] / E_i['qc']:.2f}x):")
    o(f"- compute, INT8 -> TERNARY PE: array {E_arr['int8'] / E_arr['tern']:.2f}x, {dc1:.1f} uJ ({100 * dc1 / tot:.1f} %)")
    ec = {v: sum(E[f"{v}_{l}"]["arr"] + E[f"{v}_{l}"]["wd"] for l in ("L2", "L4")) / 2 for v in ("int8c", "tern", "int8")}
    o(f"  - of which arithmetic on identical operands (INT8c / TERNARY, s8kd blocks) {ec['int8c'] / ec['tern']:.2f}x and "
      f"dense weight statistics (INT8 / INT8c) {ec['int8'] / ec['int8c']:.2f}x (array + w-reg pJ / block-op, mean L2 / L4)")
    o(f"- compute, TERNARY -> QC PE: array {E_arr['tern'] / E_arr['qc']:.2f}x, {dc2:.1f} uJ ({100 * dc2 / tot:.1f} %)")
    o(f"- weight storage / traffic, int8 -> 2-b trits: weight SRAM {(E_wrd['int8'] + E_wlk['int8']) / (E_wrd['tern'] + E_wlk['tern']):.2f}x, "
      f"{dw1:.1f} uJ ({100 * dw1 / tot:.1f} %)")
    o(f"- weight storage / traffic, trits -> QC codes: weight SRAM {(E_wrd['tern'] + E_wlk['tern']) / (E_wrd['qc'] + E_wlk['qc']):.2f}x, "
      f"{dw2:.1f} uJ ({100 * dw2 / tot:.1f} %)")
    for e in (20, 70):
        t2 = E_ii[("int8", e)] - E_ii[("qc", e)]
        dd = bits["int8"] * e * 1e-6 - bits["qc"] * e * 1e-6 - E_w2
        o(f"- scenario (ii) {e} pJ / b: INT8 -> QC saves >= {t2:.1f} uJ ({E_ii[('int8', e)] / E_ii[('qc', e)]:.2f}x), "
          f"of which compute {dc1 + dc2:.1f} uJ ({100 * (dc1 + dc2) / t2:.1f} %) and weight traffic (DRAM, minus QC's "
          f"on-chip SRAM) {dd:.1f} uJ ({100 * dd / t2:.1f} %); TERNARY -> QC >= {E_ii[('tern', e)] - E_ii[('qc', e)]:.1f} uJ")
    o("\n## 6. Caveats\n")
    o("- Pre-CTS netlists, wire-load model, ideal clock (no clock-tree power; INT8 has the most registers / clock gates), "
      "no P&R; tt 25 C leakage.  Same flow and settings for all three variants.")
    o("- Activity from two passes of one image (L2, L4: 2304 steps each); the whole-image array energy uses their mean "
      f"(QC model {E_arr['qc']:.1f} uJ vs {E_qc_meas:.1f} uJ measured in-chip: row A2' rescales all variants to the in-chip "
      "QC number).  The zero-delay rows bound the glitch contribution (SDF / zd ratio per point in section 3).")
    o("- No operand isolation / zero-skipping in any PE (v2 has none either).  The activations of these passes are 57 % "
      "(L2) and 94 % (L4) zero lanes (ReLU + padding), and the weight register reloads every cycle; an INT8 design with "
      "zero-gated multipliers or weight-stationary reuse would cut its array energy, so INT8 compute here is an upper "
      "estimate for a different design point, exact for this dataflow.")
    o("- INT8 weights are dense_s0's (realistic dense weight statistics) but driven with the s8kd activation stream (the "
      "same stream for all variants); INT8c (s8kd blocks as int8) isolates the arithmetic: same operands as QC.")
    o("- Accuracy is not part of this ablation (dense_s0 and s8kd are different networks); every variant runs the same "
      f"{CYC}-cycle schedule.")
    o("- Weight memory: linear per-bit model of one compiled 4096x80 macro (larger / wider macros, periphery sharing, "
      "low-leakage or power-gated arrays would lower the dense variants' cost); scenario (ii) is a lower bound for "
      "TERNARY / INT8 (no on-chip weight buffer, area and energy) and charges QC its measured on-chip SRAM.")
    o("- fmax: all variants close 3.3 ns (synthesis target); the 2.0 ns probe is one extra synthesis per variant, not a "
      "sweep.  At 400 MHz (tt) every variant has margin (tt fmax at 3.3 ns >= 466 MHz), so throughput is equal.")
    fn = os.path.join(R, "ablation.md")
    keep = ""                                         # the Kb = 2 section of report3.py, if present
    if os.path.exists(fn) and "## 7. Kb = 2" in open(fn).read():
        t = open(fn).read()
        keep = "\n" + t[t.index("## 7. Kb = 2"):]
        out.insert(2, "Sections 1-6: Kb = 1 (v2 array, one block per PE per cycle).  Section 7: Kb = 2 (v3 array, two "
                   "blocks per PE per cycle; `report3.py`).\n")
    open(fn, "w").write("\n".join(out) + "\n" + keep)
    D = os.path.join(R, "ablation")
    shutil.rmtree(D, ignore_errors=True)
    os.makedirs(D)
    for v in V:
        for p in glob.glob(os.path.join(L, "out", v, "*.txt")):
            b = os.path.basename(p)
            if b.endswith("_cells.txt"):                     # drop the per-clock-gate rows (size)
                open(os.path.join(D, b), "w").writelines(x for x in open(p) if "clk_gate" not in x)
            elif b.startswith(("power_", "gls_", "sdf_")):
                shutil.copy(p, os.path.join(D, b))
    for p in glob.glob(os.path.join(L, "out", "*", "qab_*_w*", "*.txt")):
        shutil.copy(p, os.path.join(D, os.path.basename(os.path.dirname(p)) + "_" + os.path.basename(p)))
    shutil.copy(os.path.join(L, "vec", "stats.txt"), os.path.join(D, "vec_stats.txt"))
    shutil.copy(os.path.join(L, "rtl.txt"), os.path.join(D, "rtl.txt"))
    print("\n".join(out))


if __name__ == "__main__":
    main()
