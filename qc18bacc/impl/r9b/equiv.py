#!/usr/bin/env python3
"""R9b structural equivalence of the partitioned chip netlist vs the r8a_rp netlist (pure regrouping check).
    python3 -I equiv.py <old dump.txt> <new dump.txt> <change_names.log>
Both dumps (dump.tcl) are the flat leaf netlists as OpenROAD links them.  New leaf names map to old ones through the
hub prefix (u_hub/) and DC's change_names log (qb_chip / qb_hub cells: u_top/X -> u_top_X).  Inserted hub split
buffers (r9b_sb_*, one input / one output) are made transparent (their I / Z nets merged).  The check: identical
instance set and masters, and every old net's terminal set {(instance, pin) | chip port} equals exactly one new net's
terminal set -> the two netlists are the same graph (same function), up to names and the split buffers."""
import sys
from collections import defaultdict

old, new, cnl = sys.argv[1:4]
ren = {"qb_chip": {}, "qb_hub": {}}
for ln in open(cnl):
    f = ln.split()
    if len(f) == 4 and f[1] == "cell" and f[0] in ren:
        ren[f[0]][f[3]] = f[2]


def mapname(n):
    if n.startswith("u_hub/"):
        p = n[6:].split("/", 1)
        c = ren["qb_hub"].get(p[0], p[0])
        return c + ("/" + p[1] if len(p) > 1 else "")
    p = n.split("/", 1)
    c = ren["qb_chip"].get(p[0], p[0])
    return c + ("/" + p[1] if len(p) > 1 else "")


def load(path, m):
    inst, nets = {}, []
    for ln in open(path):
        f = ln.split()
        if f[0] == "I":
            inst[m(f[1])] = f[2]
        elif f[0] == "N":
            nets.append(f[1:])
    return inst, nets


oi, on = load(old, lambda x: x)
ni_raw = {}
for ln in open(new):
    f = ln.split()
    if f[0] == "I":
        ni_raw[f[1]] = f[2]
ni = {mapname(k): v for k, v in ni_raw.items()}
split = {mapname(k) for k in ni_raw if "r9b_sb_" in k}
miss = [k for k in oi if k not in ni]
extra = [k for k in ni if k not in oi and k not in split]
mm = [k for k in oi if k in ni and oi[k] != ni[k]]
print("EQUIV instances old %d new %d (split buffers %d); missing in new %d, extra in new %d, master mismatches %d"
      % (len(oi), len(ni), len(split), len(miss), len(extra), len(mm)))
for k in (miss[:5] + extra[:5] + mm[:5]):
    print("  e.g.", k, oi.get(k), ni.get(k))


def term(t, m):
    if t.startswith("PORT:"):
        return t
    if ":" in t:
        a, b = t.split(":", 1)
        return m(a) + ":" + b.split("@")[0]
    return m(t)


# pin-level terminal sets (QB_PINS dumps).  Constant nets (no driver, or a TIEL / TIEH cell) are compared as a
# pin -> constant map instead (DC's group re-shares tie cells / 1'b0 between the hub and the top).
def sig(ts):
    return tuple(sorted(ts))


def const_of(f, insts, m):
    name, f = f[0], f[1:]
    d = f[0]
    if d == "-":
        return "1" if "Logic1" in name else ("0" if "Logic0" in name else "U")
    dm = insts.get(m(d.split(":")[0]))
    if dm and dm.startswith("TIEL"):
        return "0"
    if dm and dm.startswith("TIEH"):
        return "1"
    return None


osig, oconst = {}, {}
for f in on:
    c = const_of(f, oi, lambda x: x)
    f = f[1:]
    ts = [term(t, lambda x: x) for t in f if t != "-"]
    if c is not None:
        for t in ts[1:] if f[0] != "-" else ts:
            oconst[t] = c
        continue
    if ts:
        osig[sig(ts)] = osig.get(sig(ts), 0) + 1
# new: merge nets through the split buffers
par = {}
def find(x):
    while par.get(x, x) != x:
        par[x] = par.get(par[x], par[x]); x = par[x]
    return x
nterms = []
by_buf = defaultdict(list)
nconst = {}
for k, f in enumerate([ln.split()[1:] for ln in open(new) if ln.startswith("N ")]):
    c = const_of(f, ni, mapname)
    f = f[1:]
    ts = [term(t, mapname) for t in f if t != "-"]
    if c is not None:
        for t in ts[1:] if f[0] != "-" else ts:
            nconst[t] = c
        ts = []
    nterms.append(ts)
    for t in ts:
        if t.split(":")[0] in split:
            by_buf[t.split(":")[0]].append(k)
for b, ks in by_buf.items():
    for k in ks[1:]:
        par[find(k)] = find(ks[0])
groups = defaultdict(list)
for k, ts in enumerate(nterms):
    groups[find(k)] += [t for t in ts if t.split(":")[0] not in split]
nsig = {}
for g, ts in groups.items():
    if ts:
        nsig[sig(ts)] = nsig.get(sig(ts), 0) + 1
same = sum(min(v, nsig.get(k, 0)) for k, v in osig.items())
print("EQUIV nets old %d new %d (after split-buffer merge); identical terminal sets %d; old-only %d new-only %d"
      % (sum(osig.values()), sum(nsig.values()), same, sum(osig.values()) - same, sum(nsig.values()) - same))
cm = [t for t in set(oconst) | set(nconst) if oconst.get(t, "x") != nconst.get(t, "x")]
print("EQUIV constant pins old %d new %d, pins with a different constant / missing %d" % (len(oconst), len(nconst), len(cm)))
for t in cm[:5]:
    print("  const diff", t, oconst.get(t), nconst.get(t))
od = [k for k in osig if osig[k] > nsig.get(k, 0)][:3]
nd = [k for k in nsig if nsig[k] > osig.get(k, 0)][:3]
for k in od:
    print("  old-only", k[:6])
for k in nd:
    print("  new-only", k[:6])
