#!/usr/bin/env python3
"""impl/r7b (results/r7b.md): nets of the sliced S logic that span several column slices (cause of the R7b repair-buffer
growth).  python3 -I xslice.py DUMP GRP7 OUT
Column of a terminal: S-slice cell S<c> -> c, SX -> X, column block pin -> c, S / map macro -> column (slice.py seeds);
other groups / macros / ports -> ignored.  For every net with >= 1 S-slice terminal: the set of columns; span =
(max - min) column pitch x 390 um.  Output: counts by number of distinct columns and span, by driver kind, and the
summed span (a lower bound of the extra horizontal wire the slicing imposes)."""
import re
import sys
from collections import Counter, defaultdict

dump, gf, out = sys.argv[1:4]
COL = re.compile(r"g_c_(\d+)__u_col")
SM = re.compile(r"u_top/g_s_(\d+)__u_m/")
BM = re.compile(r"u_top/g_map_(\d+)__g_mm_(\d+)__u_m/")
lab = {}
for ln in open(gf):
    f = ln.split()
    if f[1].startswith("S"):
        lab[f[0]] = f[1][1]
def col(t):
    if t == "-" or t.startswith("PORT:"):
        return None
    i = t.split(":")[0]
    if i in lab and ":" not in t:
        return lab[i]
    m = COL.search(i)
    if m and ":" in t:
        return m.group(1)
    m = SM.search(i + "/")
    if m:
        return str(int(m.group(1)) % 8)
    m = BM.search(i + "/")
    if m:
        return str(4 * int(m.group(1)) + int(m.group(2)))
    return None
def kind(t):
    i = t.split(":")[0]
    if COL.search(i):
        return "blk." + re.sub(r"\[.*", "", t.split(":")[1].split("@")[0]) if ":" in t else "blk"
    for p, k in (("u_prm/", "prm"), ("u_head/", "head"), ("g_s_", "Smac"), ("g_map_", "map")):
        if p in i:
            m = re.search(r"/([a-z][a-z0-9_]*?)_reg", i)
            return k + ("." + m.group(1) if m else "")
    m = re.search(r"^u_top/([a-z][a-z0-9_]*?)_reg", i)
    return "glue." + m.group(1) if m else "glue"
H = Counter(); SP = Counter(); K = defaultdict(lambda: [0, 0.0]); tot = 0.0; n_all = 0
for ln in open(dump):
    if not ln.startswith("N "):
        continue
    f = ln.split()
    ts = f[2:]
    cs = [col(t) for t in ts]
    if not any(c is not None and (t.split(":")[0] in lab) for c, t in zip(cs, ts)):
        continue
    n_all += 1
    cc = {c for c in cs if c is not None and c != "X"}
    nc = len(cc)
    H[min(nc, 8)] += 1
    if nc >= 2:
        sp = (max(map(int, cc)) - min(map(int, cc))) * 390.0
        SP[int(sp // 390)] += 1
        tot += sp
        k = kind(f[2])
        K[k][0] += 1; K[k][1] += sp
with open(out, "w") as fh:
    fh.write(f"# xslice [S, from the netlist + slice labels]: {n_all} nets with an S-slice terminal\n")
    fh.write("# distinct columns per net: " + " ".join(f"{k}:{H[k]}" for k in sorted(H)) + "\n")
    fh.write("# column span (pitches of 390 um) of nets with >= 2 columns: " + " ".join(f"{k}:{SP[k]}" for k in sorted(SP)) + "\n")
    fh.write(f"# summed span {tot / 1e6:.2f} m (lower bound of horizontal wire across slices)\n")
    fh.write("# driver kind | nets >= 2 columns | summed span m\n")
    for k, (n, s) in sorted(K.items(), key=lambda kv: -kv[1][1])[:25]:
        fh.write(f"{k:30s} {n:7d} {s / 1e6:7.2f}\n")
print("XSLICE done")
