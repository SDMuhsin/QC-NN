#!/usr/bin/env python3
"""R12 Q1: repair inflation of the hub between the init netlist and a placed checkpoint (results/r12.md).
    python3 -I q1.py <r12_dump_init.txt> <r12_dump.txt> <dumpdb.txt> <netcls2.txt> <ovf10.py> <outdir>
Inputs: q1dump.tcl of init.odb and of the placed db; impl/r9b/dumpdb.tcl connectivity and impl/r9b/cone.py classes of
the placed db; the class grouping grp() is taken from impl/r10b/ovf10.py (not copied).
Instances present after placement but not in init = added (prefix wire / fanout / max_length / load_slew / max_cap =
the repair_design branch that created it; TIE* = tie cells); same name + other master = resized; init-only = removed
(remove_buffers).  Repair trees: from every net driven by a non-added cell or a port, walk forward through added
buffers; tree fanout = leaf sinks, tree HPWL = bbox of driver + leaves (cell centres / port centres)."""
import ast, re, sys
from collections import Counter, defaultdict
fi, fp, fd, fc, fo, od = sys.argv[1:7]
src = open(fo).read()
fn = [n for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name == "grp"][0]
ns = {}; exec(compile(ast.Module(body=[fn], type_ignores=[]), fo, "exec"), ns); grp = ns["grp"]
def rd(f):
    A, I, P = {}, {}, {}
    for ln in open(f):
        t = ln.split()
        if t[0] == "M": A[t[1]] = float(t[2])
        elif t[0] == "I": I[t[1]] = (t[2], float(t[3]), float(t[4]))
        elif t[0] == "P": P[t[1]] = (float(t[2]), float(t[3]))
    return A, I, P
A, I0, _ = rd(fi); A1, I1, P = rd(fp); A.update(A1)
mac = lambda m: A.get(m, 0) > 1000
std = lambda I: sum(A[m] for m, x, y in I.values() if not mac(m))
a0, a1 = std(I0), std(I1)
added = {n for n in I1 if n not in I0}; removed = {n for n in I0 if n not in I1}
rsz = {n for n in I1 if n in I0 and I1[n][0] != I0[n][0]}
pref = lambda n: "tie" if I1[n][0].startswith("TIE") else re.sub(r"\d+$", "", n.split("/")[-1]) if re.match(r"^(wire|fanout|max_length|load_slew|max_cap|split|rebuffer|gain)\d+$", n) else "other:" + re.sub(r"\d+", "N", n)[:30]
L = []
L.append("# R12 Q1 repair inflation [S] (std cells only; macros excluded)")
L.append("init std area %.0f um2 (%d inst) -> placed %.0f um2 (%d inst): delta %+.0f um2" % (a0, len(I0), a1, len(I1), a1 - a0))
rem_a = sum(A[I0[n][0]] for n in removed)
L.append("removed (remove_buffers, init-only)  %7d inst  %+10.0f um2" % (len(removed), -rem_a))
rz = sum(A[I1[n][0]] - A[I0[n][0]] for n in rsz)
up = sum(1 for n in rsz if A[I1[n][0]] > A[I0[n][0]])
L.append("resized (same name, other master)     %7d inst  %+10.0f um2  (%d up, %d down)" % (len(rsz), rz, up, len(rsz) - up))
PA = Counter(); PN = Counter()
for n in added: k = pref(n); PA[k] += A[I1[n][0]]; PN[k] += 1
for k, v in PA.most_common(): L.append("added %-30s  %7d inst  %+10.0f um2" % (k, PN[k], v))
L.append("check: removed + resized + added = %+.0f um2" % (-rem_a + rz + sum(PA.values())))
# resized split by masters family
RM = Counter()
for n in rsz: RM[re.sub(r"D\d+$", "", I1[n][0])] += A[I1[n][0]] - A[I0[n][0]]
L.append("resize area by cell function (top 8): " + ", ".join("%s %+.0f" % kv for kv in RM.most_common(8)))
# connectivity
drv = {}; snk = {}; outnet = defaultdict(list)
for ln in open(fd):
    if not ln.startswith("N "): continue
    t = ln.split(); net, d, s = t[1], t[2], t[3:]
    drv[net] = d; snk[net] = s
    if d != "-" and not d.startswith("PORT:"): outnet[d.rsplit(":", 1)[0]].append(net)
cls = {}
for ln in open(fc):
    t = ln.split()
    if len(t) >= 2: cls[t[0]] = t[1]
def pos(p):
    if p.startswith("PORT:"): return P.get(p[5:])
    i = I1.get(p.rsplit(":", 1)[0]); return (i[1], i[2]) if i else None
buf = {n for n in added if PN and pref(n) != "tie"}
rows = []
for net, d in drv.items():
    di = d.rsplit(":", 1)[0] if not d.startswith("PORT:") else None
    if d == "-" or (di in buf): continue
    nb, ab, leaves, st, kinds = 0, 0.0, [], [net], Counter()
    while st:
        x = st.pop()
        for s in snk.get(x, []):
            si = s.rsplit(":", 1)[0]
            if si in buf:
                nb += 1; ab += A[I1[si][0]]; kinds[pref(si)] += 1; st += outnet.get(si, [])
            else: leaves.append(s)
    pts = [p for p in [pos(d)] + [pos(s) for s in leaves] if p]
    hp = (max(p[0] for p in pts) - min(p[0] for p in pts) + max(p[1] for p in pts) - min(p[1] for p in pts)) if pts else 0.0
    rows.append((net, grp(cls.get(net, "unknown")), nb, ab, len(leaves), hp, kinds))
RC = Counter(); RN = Counter()
for n in rsz:
    for o in outnet.get(n, [])[:1]: k = grp(cls.get(o, "unknown")); RC[k] += A[I1[n][0]] - A[I0[n][0]]; RN[k] += 1
L.append("# resize area by class of the resized cell's output net (top 10): " + ", ".join("%s %+.0f (%d)" % (k, v, RN[k]) for k, v in RC.most_common(10)))
tb = sum(r[3] for r in rows); L.append("repair-buffer area in trees %.0f um2 in %d trees of %d (driver nets)" % (tb, sum(1 for r in rows if r[2]), len(rows)))
C = defaultdict(lambda: [0, 0, 0.0, Counter(), [], []])
for r in rows:
    c = C[r[1]]; c[0] += 1
    if r[2]: c[1] += r[2]; c[2] += r[3]; c[3].update(r[6]); c[4].append(r[4]); c[5].append(r[5])
def q(v, f):
    v = sorted(v); return v[min(len(v) - 1, int(f * len(v)))] if v else 0
L.append("# per driver class: trees, buffered trees, buffers, buffer area, share; reason mix (prefix counts); fanout / HPWL p50/p90/max of buffered trees")
for k, c in sorted(C.items(), key=lambda kv: -kv[1][2])[:16]:
    L.append("CLS %-22s trees %6d buffered %6d bufs %6d area %8.0f um2 %5.1f %% | %s | fo %d/%d/%d hpwl %.0f/%.0f/%.0f um" % (
        k, c[0], len(c[4]), c[1], c[2], 100 * c[2] / max(1, tb), " ".join("%s %d" % kv for kv in c[3].most_common(4)),
        q(c[4], .5), q(c[4], .9), max(c[4] or [0]), q(c[5], .5), q(c[5], .9), max(c[5] or [0])))
# fanout / HPWL bins of all buffered trees
L.append("# buffered trees by leaf fanout bin: trees, buffers, area")
for lo, hi in ((1, 1), (2, 4), (5, 16), (17, 64), (65, 256), (257, 10 ** 9)):
    s = [r for r in rows if r[2] and lo <= r[4] <= hi]
    L.append("FO %4d-%-10d trees %6d bufs %6d area %8.0f um2" % (lo, hi, len(s), sum(r[2] for r in s), sum(r[3] for r in s)))
L.append("# buffered trees by HPWL bin (um): trees, buffers, area")
for lo, hi in ((0, 100), (100, 300), (300, 757), (757, 1500), (1500, 3000), (3000, 1e9)):
    s = [r for r in rows if r[2] and lo <= r[5] < hi]
    L.append("HPWL %5d-%-6.0f trees %6d bufs %6d area %8.0f um2" % (lo, min(hi, 99999), len(s), sum(r[2] for r in s), sum(r[3] for r in s)))
L.append("# top 20 source nets by added buffer area")
for r in sorted(rows, key=lambda r: -r[3])[:20]:
    L.append("TOP %-48s %-20s bufs %4d area %7.0f um2 fo %5d hpwl %6.0f um %s" % (r[0][:48], r[1], r[2], r[3], r[4], r[5], " ".join("%s %d" % kv for kv in r[6].most_common(3))))
open(od + "/q1_repair.txt", "w").write("\n".join(L) + "\n"); print("\n".join(L))
