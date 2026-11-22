#!/usr/bin/env python3
"""R9b: south-hub membership of the r8a_rp chip netlist, at the hierarchy level DC can group after `ungroup u_top`.
    python3 -I part.py <dump.txt (dump.tcl)> <grp0.txt (impl/r6a/cuts.py --head-south --split-w --groups)> <outprefix>
Hub (H) = cuts.py group S (S / B / IMG / params / FC macros, prm, head, S-side u_top glue: write-back, rotators,
S-read / map-read paths, slice flags, host image / params write stages)
  + cuts.py WA 'glue' (comb only: the S-read / map-read rotator ends that cuts.py homed with their qb_act2 sinks)
  + chip-level head configuration / image-in-flight registers (c_*, busy, img_free, nfo, nst)
  + chip-level comb / buffers by majority of their sinks' labels (then drivers').
Top (T) = everything else (sequencer, act supply + g_dist, N glue, W glue, host IO registers g_hpn_*, err).
Units for DC (after `ungroup u_top`): chip-level leaves, u_top leaves (u_top/<x>), and hierarchical children of u_top /
qb_chip (u_top/<h>, u_head) labelled by the majority of their leaves (purity printed).
Out: <out>_cells.txt (DC cell names of the hub, one per line), <out>_units.txt (unit label n_H n_T), stdout summary."""
import re
import sys
from collections import Counter, defaultdict

dump, grp, out = sys.argv[1:4]
CHIP_H = re.compile(r"^(c_m0|c_sh|c_last|c_stem|c_nfo|c_nst|c_ncls|c_nrows|busy|img_free|nfo|nst)_reg")
lab, kind, area, master, wa_glue = {}, {}, {}, {}, []
PT = re.compile(r"^u_top/pt_reg")      # pass table (static per program): read by the write-back logic -> hub
for ln in open(grp):
    n, g, sub = ln.split()[:3]
    if PT.match(n):
        g = "S"
    lab[n] = "H" if g == "S" or (g == "WA" and sub == "glue") else "T"
    if g == "WA" and sub == "glue":
        wa_glue.append(n)
    kind[n] = sub
nets = []
for ln in open(dump):
    f = ln.split()
    if f[0] == "I":
        master[f[1]], area[f[1]] = f[2], float(f[3])
        if f[1] not in lab:                              # macros / blocks
            m = f[2]
            lab[f[1]] = "B" if m == "qb_col_blk" else ("T" if m[:4] in ("qb_w", "qb_d") else "H")
    elif f[0] == "N":
        nets.append((f[2], f[3:]))
iname = lambda t: t.split(":")[0]
# WA glue must be comb only
wa_cells = [n for n in wa_glue if n in master]
wa_seq = [n for n in wa_cells if re.match(r"(DF|EDF|SDF|LH|LN|CKLN)", master[n])]
# chip-level cells
chip = [n for n in lab if "/" not in n and master.get(n) not in ("qb_col_blk",) and not master.get(n, "qb_").startswith("qb_")]
for n in chip:
    lab[n] = None
    if "_reg" in n:
        lab[n] = "H" if CHIP_H.match(n) else "T"
fo, fi = defaultdict(list), defaultdict(list)
for d, ss in nets:
    di = iname(d)
    for t in ss:
        fo[di].append(iname(t)); fi[iname(t)].append(di)
todo = [n for n in chip if lab[n] is None]
for direction in (fo, fi):
    for it in range(100):
        new = {}
        for n in todo:
            if lab[n] is None:
                c = Counter(lab.get(x) for x in direction.get(n, ()) if lab.get(x) in ("H", "T"))
                if c:
                    new[n] = c.most_common(1)[0][0]
        lab.update(new)
        if not new:
            break
for n in todo:
    if lab[n] is None:
        lab[n] = "T"
# u_core leaves (DC buffers between the top and the column pins): those driving a column north / west pin (act, ctl,
# cd, t2, rst_n, clk) belong to the top, whatever cuts.py's propagation said
NPIN = re.compile(r":(act|ctl|cd|t2|rst_n|clk)[\[@]")
for d, ss in nets:
    di = iname(d)
    if di.startswith("u_top/u_core/") and di in master and master[di] != "qb_col_blk" and any(NPIN.search(t) for t in ss):
        lab[di] = "T"
# clock gates: an ICG (CKLN*) takes the majority label of the flops it gates, and the minority leaf flops it gates
# (chip-level / u_top leaves only) follow it, so that no gated clock crosses the hub boundary
nflip = 0
for n, m in master.items():
    if not m.startswith("CKLN") or lab.get(n) not in ("H", "T"):
        continue
    g = [x for x in fo.get(n, ()) if lab.get(x) in ("H", "T")]
    c = Counter(lab[x] for x in g)
    if not c:
        continue
    l = c.most_common(1)[0][0]
    lab[n] = l
    for x in g:
        if lab[x] != l and ("/" not in x or (x.startswith("u_top/") and x.count("/") == 1)):
            lab[x] = l; nflip += 1
print("PART icg flops moved with their gate %d" % nflip)
# units
def unit(n):
    p = n.split("/")
    if p[0] == "u_top" and len(p) > 2:
        return n if p[1] == "u_core" else "u_top/" + p[1]     # u_core is flattened in DC (leaves + 8 blocks)
    if p[0] == "u_top":
        return n
    if len(p) > 1:
        return p[0]
    return n
U = defaultdict(Counter); UA = defaultdict(Counter)
for n, l in lab.items():
    if n in master:
        U[unit(n)][l] += 1; UA[unit(n)][l] += area[n]
cells, mixed = [], []
with open(out + "_units.txt", "w") as fh:
    for u, c in sorted(U.items()):
        l = "B" if c["B"] else ("H" if UA[u]["H"] >= UA[u]["T"] else "T")
        if l == "H":
            cells.append(u)
        if len(c) > 1 and u.count("/") <= 1 and ("/" in u and not u.startswith("u_top/U") or u == "u_head"):
            mixed.append((u, dict(c)))
        if "/" in u.replace("u_top/", "", 1) or u in ("u_head",) or (u.startswith("u_top/") and not re.match(r"u_top/(U\d+|.*_reg)", u)) and sum(c.values()) > 1:
            fh.write(f"{u} {l} {c['H']} {c['T']} {c['B']} {UA[u]['H']:.1f} {UA[u]['T']:.1f}\n")
with open(out + "_cells.txt", "w") as fh:
    fh.write("\n".join(cells) + "\n")
tot = Counter(); ta = Counter()
for u, c in U.items():
    l = "B" if c["B"] else ("H" if UA[u]["H"] >= UA[u]["T"] else "T")
    tot[l] += sum(c.values()); ta[l] += sum(UA[u].values())
print("PART units H %d (cells %d, %.4f mm2 incl. macros) T cells %d (%.4f mm2) B %d" % (len(cells), tot["H"], ta["H"] / 1e6, tot["T"], ta["T"] / 1e6, tot["B"]))
print("PART WA glue cells moved to hub %d (sequential %d)" % (len(wa_cells), len(wa_seq)))
print("PART chip-level H %d T %d" % (sum(1 for n in chip if lab[n] == "H"), sum(1 for n in chip if lab[n] == "T")))
for u, c in mixed[:40]:
    print("PART mixed unit", u, c)
