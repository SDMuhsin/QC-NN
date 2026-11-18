#!/usr/bin/env python3
"""R23 (results/r23.md): which logical column pairs share hub logic.  For every std cell, the set of logical columns
(S lane L % 8, params k, hub column ports by x) reachable within QB23_HOP [2] nets (nets <= QB23_MAXD [64] pins), by
net class of the cell's nets.  Prints the pair matrix (cells touching exactly 2 columns) and the mask-size histogram.
    python3 -I pair23.py <aff23 dump> <netcls2.txt> [class regex]"""
import os, re, sys, collections as C, ast
fd, fn = sys.argv[1:3]; RX = re.compile(sys.argv[3]) if len(sys.argv) > 3 else None
HOP, MAXD, X0 = int(os.environ.get("QB23_HOP", "2")), int(os.environ.get("QB23_MAXD", "64")), 860.0
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "..", "r10b", "ovf10.py")).read()
fnd = [n for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name == "grp"][0]
ns = {}; exec(compile(ast.Module(body=[fnd], type_ignores=[]), "ovf10.py", "exec"), ns); grp = ns["grp"]
cls = {}
for ln in open(fn):
    f = ln.split()
    if len(f) >= 2: cls[f[0].replace("\\", "")] = grp(f[1])
acol, ismac, isbuf, nets, ncl = [], [], [], [], []
BUF = re.compile(os.environ.get("QB23_BUF", r"^(BUFF|CKBD|INV|CKND|DEL)"))
MERGE = os.environ.get("QB23_MERGE", "1") == "1"            # nets joined through repair buffers / inverters
for ln in open(fd):
    t = ln.split()
    if t[0] == "I":
        c = -1
        if t[5] == "1":
            m = re.search(r"g_s_(\d+)__u_m", t[6]); p = re.search(r"g_pm_(\d+)_", t[6])
            if m: c = int(m.group(1)) % 8
            elif p and int(p.group(1)) < 8: c = int(p.group(1))
        acol.append(c); ismac.append(t[5] == "1"); isbuf.append(MERGE and bool(BUF.match(t[2])))
    elif t[0] == "N":
        ob = []
        for tk in t[2:]:
            if tk[0] == "p":
                x = float(tk[1:].split(":")[0])
                ob.append(-1 - min(int((x - X0) // 390), 7) if x >= X0 else None)   # port of column c -> -1 - c
            else: ob.append(int(tk))
        nets.append([o for o in ob if o is not None]); ncl.append(cls.get(t[1].replace("\\", ""), "unclassified"))
if MERGE:                                                   # union-find over nets sharing a buffer cell
    par = list(range(len(nets)))
    def fnd(a):
        while par[a] != a: par[a] = par[par[a]]; a = par[a]
        return a
    bn = C.defaultdict(list)
    for k, ob in enumerate(nets):
        for o in ob:
            if o >= 0 and isbuf[o]: bn[o].append(k)
    for ks in bn.values():
        for k in ks[1:]: par[fnd(k)] = fnd(ks[0])
    grpn, gcl = C.defaultdict(set), {}
    for k, ob in enumerate(nets):
        r = fnd(k); grpn[r].update(o for o in ob if not (o >= 0 and isbuf[o]))
        if r == k or r not in gcl: gcl[r] = ncl[k] if r == k else gcl.get(r, ncl[k])
    nets = [sorted(v) for v in grpn.values()]; ncl = [gcl[r] for r in grpn]
nets_all = len(nets)
keep = [k for k, ob in enumerate(nets) if len(ob) <= MAXD]
nets = [nets[k] for k in keep]; ncl = [ncl[k] for k in keep]
o2n = C.defaultdict(list)
for k, ob in enumerate(nets):
    for o in ob: o2n[o].append(k)
def colof(o):
    if o < 0: return -1 - o
    return acol[o] if acol[o] >= 0 else None
pairs, hist, n = C.Counter(), C.Counter(), 0
for i in range(len(acol)):
    if ismac[i] or isbuf[i] or i not in o2n: continue
    if RX and not any(RX.search(ncl[k]) for k in o2n[i]): continue
    seen, front, mask = {i}, [i], set()
    for _ in range(HOP):
        nxt = []
        for o in front:
            for k in o2n.get(o, []):
                for q in nets[k]:
                    if q in seen: continue
                    seen.add(q); c = colof(q)
                    if c is not None: mask.add(c)
                    elif q >= 0 and not ismac[q]: nxt.append(q)
        front = nxt
    n += 1; hist[len(mask)] += 1
    if len(mask) == 2: pairs[tuple(sorted(mask))] += 1
print("PAIR23 merge %d: nets %d, kept (<= %d pins) %d" % (MERGE, nets_all, MAXD, len(nets)))
print("PAIR23 cells %d (class %s, hop %d); columns reached: %s" % (n, RX.pattern if RX else "all", HOP, " ".join("%d:%d" % kv for kv in sorted(hist.items()))))
byd = C.Counter()
for (a, b), v in pairs.items(): byd[b - a] += v
print("PAIR23 2-column cells by column distance |a-b|: %s" % " ".join("%d:%d" % kv for kv in sorted(byd.items())))
print("PAIR23 top pairs: %s" % " ".join("%d%d:%d" % (a, b, v) for (a, b), v in pairs.most_common(12)))
# optional: per-macro column reach (QB23_SRC = regex on the macro instance name, e.g. g_map): BFS over QB23_HOP nets
SRC = os.environ.get("QB23_SRC")
if SRC:
    mname = {}
    for ln in open(fd):
        t = ln.split()
        if t[0] == "I" and t[5] == "1" and re.search(SRC, t[6]): mname[int(t[1])] = t[6]
    for i, nm in sorted(mname.items(), key=lambda kv: kv[1]):
        seen, front, cnt = {i}, [i], C.Counter()
        for _ in range(HOP):
            nxt = []
            for o in front:
                for k in o2n.get(o, []):
                    for q in nets[k]:
                        if q in seen: continue
                        seen.add(q); c = colof(q)
                        if c is not None: cnt[c] += 1
                        elif q >= 0 and not ismac[q]: nxt.append(q)
            front = nxt
        print("PAIR23 src %s: columns reached %s" % (re.sub(r"/.*", "", nm)[-28:], " ".join("%d:%d" % (c, cnt[c]) for c in range(8))))
# optional: QB23_SMASK 1 = for the (merged) nets of the class regex, histogram of the columns of their S-macro / column-
# port terminals (direct, no hop): which column groups one net (+ its repair buffers) spans
if os.environ.get("QB23_SMASK") == "1":
    h = C.Counter()
    for k, ob in enumerate(nets):
        if RX and not RX.search(ncl[k]): continue
        m = frozenset(c for c in (colof(o) for o in ob) if c is not None)
        if len(m) >= 2: h[" ".join(map(str, sorted(m)))] += 1
        else: h["<=1 col"] += 1
    print("PAIR23 smask (class %s): %s" % (RX.pattern if RX else "all", "; ".join("{%s}:%d" % kv for kv in h.most_common(14))))
