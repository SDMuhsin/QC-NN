#!/usr/bin/env python3
"""R4 power / energy / TOPS/W of qb_chip from a PrimeTime PX run (pt_power.tcl) + the macro datatable model.

    power.py <pt_prefix> <macro_counts.txt> <dat_energy.txt> <period_ns> [ops_per_image]

pt_prefix.txt (power groups) and pt_prefix_hier.rpt (report_power -hierarchy -levels 4): PT power of the netlist
(macros: pin + ICG power only, their .lib CLK energy is 0).  Macro access energy = reads x E_read + writes x E_write
(datatable, tt) over the window (macro_counts.py), + datatable standby leakage.  Window = one steady-state image
interval [go k-1, go k) (engine image k-1, head of image k-2, IMG load of image k), so energy / image = P x window.
ops / image = 2 x executed MACs (qc18bacc/workload.py, E6_s0: 119 873 024 MAC; head FC not counted).
Breakdown: macros (datatable + PT wrapper power), PE array (u_pe), lanes (u_lf, u_lw, u_pbf, u_pbw), act supply
(u_act), clock (PT clock_network group: ICGs; pre-CTS, no tree), other (rest)."""
import re
import sys

pre, cnt_f, dat_f, per = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
ops = float(sys.argv[5]) if len(sys.argv) > 5 else 2 * 119873024

# ---- PT hierarchy
hier = []                                # (path, int, sw, leak, tot)
stack = []
num = r"([-\d.eE+]+|N/A)"
for line in open(pre + "_hier.rpt"):
    m = re.match(r"^(\s*)(\S+)(?: \((\S+)\))?\s+" + r"\s+".join([num] * 4) + r"\s+([\d.]+)\s*$", line)
    if not m:
        continue
    ind = len(m.group(1)) // 2
    stack = stack[:ind] + [m.group(2)]
    v = [0.0 if x == "N/A" else float(x) for x in m.group(4, 5, 6, 7)]
    hier.append(("/".join(stack), *v))
top = hier[0]
H = {p: v for p, *v in hier}


def parse_hier(f):
    out, st = {}, []
    for line in open(f):
        m = re.match(r"^(\s*)(\S+)(?: \((\S+)\))?\s+" + r"\s+".join([num] * 4) + r"\s+([\d.]+)\s*$", line)
        if m:
            ind = len(m.group(1)) // 2
            st = st[:ind] + [m.group(2)]
            out["/".join(st)] = [0.0 if x == "N/A" else float(x) for x in m.group(4, 5, 6, 7)]
    return out


import os
HC = parse_hier(pre + "_hierclk.rpt") if os.path.exists(pre + "_hierclk.rpt") else {}


def sumre(rx):
    """block power without its clock-network part (when the clock_network hierarchy report exists)"""
    sel = [p for p in H if re.search(rx, p)]
    sel = [p for p in sel if not any(p != q and p.startswith(q + "/") for q in sel)]
    return [sum(H[p][i] - HC.get(p, [0, 0, 0, 0])[i] for p in sel) for i in range(4)], len(sel)


groups = {}
txt = open(pre + ".txt").read()
for g in ("io_pad", "memory", "black_box", "clock_network", "register", "sequential", "combinational"):
    m = re.search(rf"^{g}\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)", txt, re.M)
    if m:
        groups[g] = [float(x) for x in m.groups()]
tp = top[1:]
cat = {}
cat["PE array"] = sumre(r"/u_top/u_core/[^/]*u_pe$")[0]
lanes = [sumre(r"/u_top/u_core/[^/]*" + x + "$")[0] for x in ("u_lf", "u_lw", "u_pbf", "u_pbw")]
cat["lanes (fused, wide, param banks)"] = [sum(l[i] for l in lanes) for i in range(4)]
cat["act supply"] = sumre(r"/u_top/u_act$")[0]
cat["sequencer + params path"] = [a + b for a, b in zip(sumre(r"/u_top/[^/]*u_seq$")[0], sumre(r"/u_top/[^/]*u_prm$")[0])]
wr = [sumre(x)[0] for x in (r"/u_top/g_(wl|s|map|img)_[^/]*u_m$", r"u_prm/g_pm_[^/]*u_m$", r"/u_head/g_fl_[^/]*u_m$",
                              r"u_seq/g_dmac_u_d[es]$")]
cat["macro wrappers (PT: pins + ICG)"] = [sum(w[i] for w in wr) for i in range(4)]
cat["sequencer + params path"] = [a - b - c for a, b, c in zip(cat["sequencer + params path"], wr[1], wr[3])]
cat["head"] = [a - b for a, b in zip(sumre(r"^[^/]+/u_head$")[0], wr[2])]
clk = HC.get(hier[0][0], groups.get("clock_network", [0, 0, 0, 0])) if HC else groups.get("clock_network", [0, 0, 0, 0])
used = [sum(cat[k][i] for k in cat) for i in range(4)]
cat["other (core BR/dec/ctl, qb_top glue, chip glue)"] = [tp[i] - used[i] - (clk[i] if HC else 0) for i in range(4)]

# ---- macro datatable model
E = {}
for line in open(dat_f):
    w = line.split()
    E[w[0]] = dict(r=float(w[2]), w=float(w[4]), sb=float(w[8]))
cyc = None
mac = {}
for line in open(cnt_f):
    if line.startswith("#"):
        cyc = float(re.search(r"window cycles ([\d.]+)", line).group(1)); continue
    w = line.split()
    mac[w[0]] = dict(n=int(w[2]), r=float(w[4]), wr=float(w[6]))
T = cyc * per * 1e-9                                               # window seconds
mdyn = {k: (v["r"] * E[k]["r"] + v["wr"] * E[k]["w"]) * 1e-12 / T for k, v in mac.items()}   # W
mleak = {k: v["n"] * E[k]["sb"] * 1e-3 for k, v in mac.items()}
mtot = sum(mdyn.values()) + sum(mleak.values())
ptot = tp[3] + mtot
print(f"# window {cyc:.0f} cycles at {per} ns ({1e3 / per:.1f} MHz) = {T * 1e6:.3f} us; ops/image {ops:.0f}")
print(f"PT netlist total W {tp[3]:.4f} (int {tp[0]:.4f} sw {tp[1]:.4f} leak {tp[2]:.4f})")
for g, v in groups.items():
    print(f"PT group {g:14s} W {v[3]:.4f}")
print(f"macro datatable dyn W {sum(mdyn.values()):.4f} leak W {sum(mleak.values()):.4f}")
for k in mac:
    print(f"  macro {k:16s} n {mac[k]['n']:3d} reads/cyc {mac[k]['r'] / cyc:6.2f} writes/cyc {mac[k]['wr'] / cyc:6.2f} "
          f"E_r {E[k]['r']:.2f} E_w {E[k]['w']:.2f} pJ  dyn W {mdyn[k]:.4f} leak W {mleak[k]:.4f}  uJ/img {(mdyn[k] + mleak[k]) * T * 1e6:.3f}")
print(f"TOTAL W {ptot:.4f}  energy/image uJ {ptot * T * 1e6:.3f}  TOPS/W {ops / (ptot * T) / 1e12:.2f}  (images/s {1 / T:.0f})")
print("# breakdown (W, uJ/image, %); macros = datatable access + standby + PT wrapper (pins, ICG); clock = PT clock_network "
      "(ICGs incl. DC clock gates, pre-CTS: no tree), counted inside the blocks below")
rows = [("macros", mtot + cat["macro wrappers (PT: pins + ICG)"][3])]
for k in ("PE array", "lanes (fused, wide, param banks)", "act supply", "sequencer + params path", "head",
          "other (core BR/dec/ctl, qb_top glue, chip glue)"):
    rows.append((k, cat[k][3]))
for k, v in rows:
    print(f"  {k:48s} W {v:.4f}  uJ/img {v * T * 1e6:.3f}  {100 * v / ptot:5.1f} %")
print(f"  {'clock network (ICGs; ' + ('separate' if HC else 'inside the blocks above') + ')':48s} W {clk[3]:.4f}  uJ/img {clk[3] * T * 1e6:.3f}  {100 * clk[3] / ptot:5.1f} %")
