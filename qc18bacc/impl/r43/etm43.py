#!/usr/bin/env python3
"""R43 (results/r43.md): second-stage ETM outlier correction after impl/r7b/etm_fix.py.
    python3 -I etm43.py <in.lib> <out.lib> [thr_ns=2.0] [ref.lib d_ns=0.5]
etm_fix.py only repairs an arc whose rise / fall FIRST values differ by > thr.  The column tt ETM keeps tables with
garbage rows at the largest data transition (act[2911] hold fall 7.26 ns / setup -8.84 ns at index_1 0.385, breakpoints
0.0942 / 0.0997 nearly coincident -> extrapolation; act[1160], pf[507/510/516] up to 3.5 ns) which OpenSTA / PT read as
-7.2 ns hold on act -> col and -3.11 ns on hub -> col pf (the ss / ff ETMs of the same block are clean).
Correction: inside every setup_* / hold_* timing group, a rise_ / fall_constraint table with ANY value outside
median(first values of that arc type) +- thr is replaced by the same edge's table of the same timing_type of the
nearest bus bit (name[i +- k]) whose table is clean.  Every replacement prints an ETM43 line; the rest is copied.
Optional ref.lib (the same block's ss ETM): a table is also bad when it leaves the ss table of the same pin / arc / edge
by more than d_ns (hold tables only: tt hold max above the ss hold max + d_ns): a tt hold requirement beyond the slow
corner's is an extraction artefact (pessimistic tt-only hold; setup / min-side differences are left alone)."""
import re
import statistics
import sys

src, dst = sys.argv[1], sys.argv[2]
thr = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
ref = sys.argv[4] if len(sys.argv) > 4 else None
dref = float(sys.argv[5]) if len(sys.argv) > 5 else 0.5
txt = open(src).read()
PINRE = re.compile(r'pin\("([^"]+)"\) \{')
TG = re.compile(r"\ttiming \(\) \{\n\t\trelated_pin : \"([^\"]+)\" ;\n\t\ttiming_type : ((setup|hold)_\w+) ;\n(.*?)\t\} /\* end of arc [^\n]*\*/", re.S)
CT = re.compile(r"\t\t(rise|fall)_constraint\([^)]*\)\{\n.*?\n\t\t\}", re.S)
VAL = re.compile(r'values \((.*?)\);', re.S)
NUM = re.compile(r'-?[0-9]+\.?[0-9]*(?:e-?[0-9]+)?')
def parse(txt):
    pins = [(m.start(), m.group(1)) for m in PINRE.finditer(txt)]
    starts = [p[0] for p in pins]
    import bisect
    tables, first = {}, {"setup": [], "hold": []}
    for g in TG.finditer(txt):
        pin = pins[bisect.bisect_right(starts, g.start()) - 1][1]
        for c in CT.finditer(txt, g.start(4), g.end(4)):
            v = [float(x) for x in NUM.findall(VAL.search(c.group(0)).group(1))]
            tables[(pin, g.group(1), g.group(2), c.group(1))] = (c.start(), c.end(), c.group(0), v)
            first[g.group(3)].append(v[0])
    return tables, first


tables, first = parse(txt)
reft = parse(open(ref).read())[0] if ref else {}
med = {k: statistics.median(v) for k, v in first.items() if v}


def bad(key):
    k = "setup" if key[2].startswith("setup") else "hold"
    v = tables[key][3]
    if any(abs(x - med[k]) > thr for x in v):
        return True
    if k == "hold" and key in reft:
        return max(v) > max(reft[key][3]) + dref
    return False


rep = []
for key in sorted(tables):
    if not bad(key):
        continue
    pin, rel, tt, edge = key
    m = re.match(r"(.*)\[(\d+)\]$", pin)
    good = None
    if m:
        base, i = m.group(1), int(m.group(2))
        for d in range(1, 64):
            for j in (i - d, i + d):
                k2 = (f"{base}[{j}]", rel, tt, edge)
                if k2 in tables and not bad(k2):
                    good = k2
                    break
            if good:
                break
    if not good:
        print(f"ETM43_KEEP {pin} {tt} {edge}: no clean neighbour")
        continue
    v, g = tables[key][3], tables[good][3]
    print(f"ETM43 {pin} {tt} {edge} [{min(v):.3f}, {max(v):.3f}] -> {good[0]} [{min(g):.3f}, {max(g):.3f}]")
    rep.append((tables[key][0], tables[key][1], tables[good][2]))
out, last = [], 0
for s, e, t in sorted(rep):
    out.append(txt[last:s]); out.append(t); last = e
out.append(txt[last:])
open(dst, "w").write("".join(out))
print(f"ETM43_DONE {dst}: {len(rep)} tables replaced of {len(tables)}, medians {med}, thr {thr}")
