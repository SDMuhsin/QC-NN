#!/usr/bin/env python3
"""R9b: refine net classes of the hub glue by their comb cone (source and destination tags), as R7a's classes.
    python3 -I cone.py <dumpdb.txt> <netcls.txt> <out netcls2.txt>
Source tag of a net = the sequential / macro / port starts of its backward comb cone (through every comb cell), e.g.
S-Q, P-Q, B-Q, I-Q, F-Q, fy-reg (u_top_g_wbq_*), reg, port; destination tag = the ends of its forward cone:
S-in (S / B macro write side), col-out (column-facing hub port), act-out (act / sequencer / top ports), reg.
Glue nets become 'glue:<main source>><main destination>'; other classes unchanged."""
import re
import sys
from collections import Counter, defaultdict

dump, ncf, out = sys.argv[1:4]
kind, mas = {}, {}
drv, sinks = {}, {}
out_nets = defaultdict(list)   # inst -> nets it drives
in_nets = defaultdict(list)    # inst -> nets it reads
for ln in open(dump):
    f = ln.split()
    if f[0] == "I":
        kind[f[1]], mas[f[1]] = f[3], f[2]
    elif f[0] == "N":
        n, d, ss = f[1], f[2], f[3:]
        drv[n], sinks[n] = d, ss
        if d != "-" and not d.startswith("PORT:"):
            out_nets[d.split(":")[0]].append(n)
        for s in ss:
            if not s.startswith("PORT:"):
                in_nets[s.split(":")[0]].append(n)
COLP = re.compile(r"PORT:u_top_(pf|pw|s_rd|w_r|t2|f_sh|w_sh|p_ld|w_ld|f_src|f_vld|w_vld)")
def stag(d):
    if d == "-":
        return "const"
    if d.startswith("PORT:"):
        return "port"
    i = d.split(":")[0]
    if kind.get(i) == "macro":
        return mas[i][3] + "-Q"   # qb_s -> s-Q
    if "g_wbq_fyq" in i or "fyi_reg" in i:
        return "fy-reg"
    return "reg"
def dtag(s):
    if s.startswith("PORT:"):
        return "col-out" if COLP.match(s) else ("act-out" if ("s_q" in s or "m_q" in s) else "top-out")
    i = s.split(":")[0]
    if kind.get(i) == "macro":
        return mas[i][3] + "-in"
    return "reg"
sys.setrecursionlimit(100000)
SRC, DST = {}, {}
def src(n, depth=0):
    if n in SRC:
        return SRC[n]
    d = drv.get(n, "-")
    i = d.split(":")[0]
    if d == "-" or d.startswith("PORT:") or kind.get(i) != "comb" or depth > 60:
        r = Counter({stag(d): 1})
    else:
        SRC[n] = Counter()
        r = Counter()
        for m in in_nets.get(i, ()):
            for k, v in src(m, depth + 1).items():
                r[k] += v
        r = Counter({k: 1 for k in r})
    SRC[n] = r
    return r
def dst(n, depth=0):
    if n in DST:
        return DST[n]
    DST[n] = Counter()
    r = Counter()
    for s in sinks.get(n, ()):
        i = s.split(":")[0]
        if s.startswith("PORT:") or kind.get(i) != "comb" or depth > 60:
            r[dtag(s)] += 1
        else:
            for m in out_nets.get(i, ()):
                for k, v in dst(m, depth + 1).items():
                    r[k] += v
    r = Counter({k: 1 for k in r})
    DST[n] = r
    return r
SP = ["s-Q", "b-Q", "p-Q", "i-Q", "f-Q", "fy-reg", "port", "reg", "const"]
DP = ["act-out", "col-out", "s-in", "b-in", "i-in", "p-in", "f-in", "top-out", "reg"]
def pick(c, order):
    for k in order:
        if c.get(k):
            return k
    return c.most_common(1)[0][0] if c else "?"
cnt = Counter()
with open(ncf) as fi, open(out, "w") as fo:
    for ln in fi:
        f = ln.split()
        if len(f) >= 2 and f[1] in ("glue", "reg:u_top_g_wbq_fyq") or (len(f) >= 2 and f[1].startswith("other")):
            s = src(f[0]); d = dst(f[0])
            c = "glue:%s>%s" % (pick(s, SP), pick(d, DP))
            if f[1].startswith("reg:"):
                c = "fyreg>" + pick(d, DP)
            f[1] = c
        cnt[f[1]] += 1
        fo.write(" ".join(f) + "\n")
for k, v in cnt.most_common(20):
    print("CONE %-28s %d" % (k, v))
