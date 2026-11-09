#!/usr/bin/env python3
"""Short result files of one DC / PrimeTime run of QC18-ACC (numbers only, safe to copy off the server).
  python3 -I qc18acc/impl/summarize.py <syn_run_dir> <out_dir>
Reads <run>/summary.txt (DC), rpt/area.rpt (report_area -hierarchy), pt_<corner>.txt and writes
  area.txt    total / macro / logic area (um2, mm2, kGE with the NAND2 area of the DC summary = ND2D1 of the library);
              per block (first-level instance of qa_top, PE array also per PE): total, macro and logic area
  timing.txt  DC summary line + per corner PT: WNS, fmax, worst path, worst paths into / out of the macros
"""
import collections
import glob
import os
import re
import socket
import sys

BLOCKS = [  # (block, first-level instance(s) of qa_top)
    ("pe_array (8x8 qa_pe + shadow chains)", ["u_array"]),
    ("drain (param RF, loader, addresses)", ["u_drain"]),
    ("ppu (8 lanes, 6 stages)", ["u_ppu"]),
    ("head (pool + FC)", ["u_head"]),
    ("agu", ["u_agu"]),
    ("xbar (S2 -> S3 rotation, code reg)", ["u_xbar"]),
    ("seq (descriptors, perf counters)", ["u_seq"]),
    ("host port + CSRs", ["u_host"]),
    ("act buffers (24 x 1024x64 + ports)", ["u_act"]),
    ("weight SRAM (6 x 4096x80)", ["u_wmem"]),
    ("param SRAM (2 x 4096x72)", ["u_pmem"]),
    ("descriptor RAM (256x32)", ["u_desc"]),
]


BLOCKS3 = [  # v3 (Kb = 2): two weight halves, 48 act macros, 16-lane PPU
    ("pe_array (8x8 qa_pe 2-block + shadow chains)", ["u_array"]),
    ("drain (param RF, loader, addresses)", ["u_drain"]),
    ("ppu (16 lanes, 6 stages)", ["u_ppu"]),
    ("head (pool + FC)", ["u_head"]),
    ("agu", ["u_agu"]),
    ("xbar (128-b kw window, code reg)", ["u_xbar"]),
    ("seq (descriptors, perf counters)", ["u_seq"]),
    ("host port + CSRs", ["u_host"]),
    ("act buffers (48 x 512x64 + ports)", ["u_act"]),
    ("weight SRAM (2 halves x 3 x 4096x80)", ["u_wmem_e", "u_wmem_o"]),
    ("param SRAM (2 x 4096x72)", ["u_pmem"]),
    ("descriptor RAM (256x32)", ["u_desc"]),
]


def main(run, out):
    os.makedirs(out, exist_ok=True)
    summ = open(os.path.join(run, "summary.txt")).read()
    area_s = float(re.search(r"cell_area_um2 (\S+)", summ).group(1))
    kge_s = float(re.search(r"gate_eq_kGE (\S+)", summ).group(1))
    nand = area_s / kge_s / 1000.0
    rows = {}
    top = None
    in_tab = False
    for line in open(os.path.join(run, "rpt", "area.rpt")):
        if line.startswith("-----"):
            in_tab = True
            continue
        t = line.split()
        if not in_tab or len(t) < 7:
            continue
        try:
            tot, comb, seq, bb = float(t[1]), float(t[3]), float(t[4]), float(t[5])
        except ValueError:
            continue
        if top is None:
            top = t[0]
        rows[t[0]] = (tot, comb, seq, bb, t[6])
    total = rows[top][0]
    macro = sum(r[3] for r in rows.values())
    logic = total - macro
    L = [f"run {os.path.basename(run.rstrip('/'))} host {socket.gethostname().split('.')[0]}",
         f"nand2_um2 {nand:.3f} (DC summary: total cell area / kGE)",
         f"total_um2 {total:.0f} total_mm2 {total / 1e6:.3f}",
         f"macro_um2 {macro:.0f} macro_mm2 {macro / 1e6:.3f} ({100 * macro / total:.1f} %)",
         f"logic_um2 {logic:.0f} logic_mm2 {logic / 1e6:.3f} logic_kGE {logic / nand / 1e3:.1f}",
         "", f"{'block':42s} {'total_um2':>10s} {'macro_um2':>10s} {'logic_um2':>10s} {'logic_kGE':>9s} {'%logic':>6s}"]
    used = 0.0
    used_m = 0.0

    def sub(prefix):
        t = sum(r[0] for k, r in rows.items() if k == prefix)
        m = sum(r[3] for k, r in rows.items() if k == prefix or k.startswith(prefix + "/"))
        return t, m

    for name, insts in (BLOCKS3 if "u_wmem_e" in rows else BLOCKS):
        t = m = 0.0
        for i in insts:
            a, b = sub(i)
            t += a
            m += b
        used += t
        used_m += m
        L.append(f"{name:42s} {t:10.0f} {m:10.0f} {t - m:10.0f} {(t - m) / nand / 1e3:9.1f} {100 * (t - m) / logic:6.1f}")
    glue = total - used
    L.append(f"{'top glue (qa_top memory port muxing)':42s} {glue:10.0f} {macro - used_m:10.0f} {glue - macro + used_m:10.0f} "
             f"{(glue - macro + used_m) / nand / 1e3:9.1f} {100 * (glue - macro + used_m) / logic:6.1f}")
    pes = [r for k, r in rows.items() if k.startswith("u_array/") and k.count("/") == 1 and "qa_pe" in r[4]]
    if pes:
        a = sum(r[0] for r in pes) / len(pes)
        L += ["", f"one PE (mean of {len(pes)} qa_pe): {a:.0f} um2 = {a / nand / 1e3:.2f} kGE; "
                  f"64 PEs {64 * a:.0f} um2, rest of u_array {rows['u_array'][0] - sum(r[0] for r in pes):.0f} um2"]
    L += ["", "hierarchy (depth <= 2, total um2):"]
    for k, r in rows.items():
        if k != top and k.count("/") <= 1 and "clk_gate" not in k and r[0] > 2000:
            L.append(f"  {k:60s} {r[0]:10.0f}  {r[4]}")
    open(os.path.join(out, "area.txt"), "w").write("\n".join(L) + "\n")

    T = ["dc " + " ".join(l for l in summ.splitlines() if l.startswith(("design", "setup_wns", "hold_wns")))]
    for f in sorted(glob.glob(os.path.join(run, "pt_*.txt"))):
        c = os.path.basename(f)[3:-4]
        for l in open(f):
            if l.startswith(("clock ", "path_", "setup_", "hold_", "macros")):
                T.append(f"{c} {l.rstrip()}")
    open(os.path.join(out, "timing.txt"), "w").write("\n".join(T) + "\n")
    print("\n".join(L[:6] + T))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
