#!/usr/bin/env python3
"""Short result files of one synthesis run of qc_snitch_cluster_top (numbers only, safe to copy off the server).
  python3 -I impl/snitch_cluster/summarize.py <syn_run_dir> <out_dir>
Reads <run>/summary.txt, rpt/area.rpt (report_area -hierarchy), rpt/power.rpt (DC), pt_<corner>.txt (PrimeTime with
impl/snitch_cluster/pt_hook.tcl) and writes into <out_dir>:
  area.txt     total / logic / macro (black-box) area, gate equivalents, area by hierarchy (depth <= 3, >= 0.5 %)
  timing.txt   DC summary lines, per corner and clock: WNS, fmax, worst path; power lines
  netlist.txt  host and path of the netlist / ddc / sdc
"""
import glob
import os
import re
import socket
import sys

NAND2_UM2 = 1.44            # ND2D1 of tcbn65gplus, the gate-equivalent unit of the flow summary


def area_rows(path):
    """report_area -hierarchy -nosplit: (name, total, pct, comb, noncomb, blackbox)"""
    rows, started = [], False
    if not os.path.exists(path):
        return rows
    for line in open(path):
        if line.startswith("-----"):
            started = True
            continue
        if not started:
            continue
        f = line.split()
        if len(f) >= 6 and re.match(r"^[0-9.]+$", f[1]) and re.match(r"^[0-9.]+$", f[2]):
            rows.append((f[0], float(f[1]), float(f[2]), float(f[3]), float(f[4]), float(f[5])))
        elif line.startswith("Total"):
            break
    return rows


def main():
    run, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    summ = open(os.path.join(run, "summary.txt")).read() if os.path.exists(os.path.join(run, "summary.txt")) else ""
    top = re.search(r"\btop (\S+)", summ).group(1) if "top " in summ else "qc_snitch_cluster_top"

    apath = os.path.join(run, "rpt", "area.rpt")
    rows = area_rows(apath)
    head = open(apath).read() if os.path.exists(apath) else ""
    hv = lambda k: float(re.search(r"^" + re.escape(k) + r"\s+([0-9.]+)", head, re.M).group(1))
    # subtree macro area: every row's local black-box area added to the row and all its ancestors
    macro = {}
    for name, a, pct, comb, seq, blk in rows:
        parts = [] if name == top else name.split("/")
        for k in range(len(parts) + 1):
            key = "/".join(parts[:k]) or top
            macro[key] = macro.get(key, 0.0) + blk
    with open(os.path.join(out, "area.txt"), "w") as fh:
        if rows:
            tot, bb = hv("Total cell area:"), hv("Macro/Black Box area:")
            fh.write("# um2 at ss (DC, report_area); macro = compiled SRAM / RF macros (area from their .db)\n")
            fh.write(f"total_um2 {tot:.0f}  logic_um2 {tot - bb:.0f} ({(tot - bb) / NAND2_UM2 / 1e3:.0f} kGE)  "
                     f"macro_um2 {bb:.0f}  macro_share {100 * bb / tot:.1f} %\n")
            fh.write(f"logic_comb_um2 {hv('Combinational area:'):.0f}  logic_seq_um2 {hv('Noncombinational area:'):.0f}  "
                     f"macros {int(hv('Number of macros/black boxes:'))}  cells {int(hv('Number of cells:'))}\n\n")
            fh.write(f"{'hierarchy (depth <= 3, >= 0.5 % of total)':<72} {'total':>10} {'%':>6} {'logic':>10} {'macro':>10}\n")
            for name, a, pct, comb, seq, blk in rows:
                depth = 0 if name == top else name.count("/") + 1
                if depth <= 3 and pct >= 0.5:
                    m = macro.get(name, 0.0)
                    label = "  " * depth + (name.split("/")[-1] if depth else name)
                    fh.write(f"{label:<72} {a:10.0f} {pct:6.1f} {a - m:10.0f} {m:10.0f}\n")
        else:
            fh.write("no area report\n")

    with open(os.path.join(out, "timing.txt"), "w") as fh:
        fh.write("# DC (wire-load or topographical, see 'topo'), ideal clocks, pre-CTS\n")
        fh.write("".join("dc " + l + "\n" for l in summ.splitlines() if l.strip()))
        for c in ("ss", "tt", "ff"):
            p = os.path.join(run, f"pt_{c}.txt")
            if os.path.exists(p):
                fh.write(f"\n# PrimeTime {c}\n")
                fh.write("".join(f"pt_{c} {l}\n" for l in open(p).read().splitlines() if l.strip()))
        pr = os.path.join(run, "rpt", "power.rpt")
        if os.path.exists(pr):
            txt = open(pr).read()
            m = re.search(r"^Total\s+(.+)$", txt, re.M)
            if m:
                fh.write(f"\n# DC report_power (ss, default activity)\ndc_power Total {m.group(1).strip()}\n")

    with open(os.path.join(out, "netlist.txt"), "w") as fh:
        host = socket.gethostname().split(".")[0]
        for ext in ("v", "ddc", "sdc", "spef"):
            f = os.path.join(os.path.realpath(run), f"{top}.{ext}")
            if os.path.exists(f):
                fh.write(f"{ext} {host}:{f} {os.path.getsize(f) / 1e6:.1f} MB\n")
        for f in sorted(glob.glob(os.path.join(run, "run.env"))):
            fh.write("".join("env " + l + "\n" for l in open(f).read().splitlines()))
    print("SUMMARY", out, *sorted(os.listdir(out)))


if __name__ == "__main__":
    main()
