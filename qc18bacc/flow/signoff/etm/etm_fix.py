#!/usr/bin/env python3
"""impl/r7b (results/r7b.md): corrected P&R copy of a column-block ETM (impl/r5b r5b_blk/qb_col_blk_<c>_ins.lib).
    python3 -I etm_fix.py <in.lib> <out.lib> [thr_ns=2.0]
R6c finding: a few input pins carry an extraction outlier on ONE edge of their setup / hold arc (tt: act[4071] rise
setup -7.05 / hold +8.18 ns while its fall arcs are -0.92 / +0.93 ns, and the 1 159 other act pins ~-0.85 / +0.87 ns;
the block's own routed PT gives act -> reg +0.53 ns slack at 2.0 ns, results/r5b.md); with them OpenSTA reports a
-5.6-ns hold violation on every column's act[4071] (act feedthrough chain act -> act_o -> next column act).
Correction: inside every setup_* / hold_* timing group, if the first value of rise_constraint and fall_constraint differ
by more than thr_ns, the table of the edge farther from the median of all pins' first values for that arc type is
replaced by the other edge's table (index_1 / index_2 / values).  Every corrected pin is printed (ETM_FIX lines).
Everything else is copied byte for byte."""
import re
import statistics
import sys

src, dst = sys.argv[1], sys.argv[2]
thr = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
txt = open(src).read()
# timing groups with a constraint type: '\ttiming () {' ... '} /* end of arc ... */'
TG = re.compile(r"(\ttiming \(\) \{\n\t\trelated_pin : \"[^\"]+\" ;\n\t\ttiming_type : (setup|hold)_\w+ ;\n)(.*?)(\t\} /\* end of arc [^\n]*\*/)", re.S)
CT = re.compile(r"(\t\t(rise|fall)_constraint\([^)]*\)\{\n.*?\n\t\t\})", re.S)
FIRST = re.compile(r'values \( "\s*(-?[0-9.]+)')
groups = list(TG.finditer(txt))
first = {"setup": [], "hold": []}
for m in groups:
    for c in CT.finditer(m.group(3)):
        first[m.group(2)].append(float(FIRST.search(c.group(1)).group(1)))
med = {k: statistics.median(v) for k, v in first.items() if v}
out, last, n = [], 0, 0
PIN = re.compile(r'pin\("([^"]+)"\) \{')
for m in groups:
    body = m.group(3)
    cs = {c.group(2): c.group(1) for c in CT.finditer(body)}
    if set(cs) != {"rise", "fall"}:
        continue
    v = {k: float(FIRST.search(t).group(1)) for k, t in cs.items()}
    if abs(v["rise"] - v["fall"]) <= thr:
        continue
    k = m.group(2)
    bad = max(v, key=lambda e: abs(v[e] - med[k]))
    good = "fall" if bad == "rise" else "rise"
    newt = cs[good].replace(good + "_constraint", bad + "_constraint", 1)
    pin = PIN.findall(txt, 0, m.start())[-1]
    print(f"ETM_FIX {pin} {k} {bad} {v[bad]:.3f} -> {v[good]:.3f} (median {k} {med[k]:.3f})")
    out.append(txt[last:m.start(3)])
    out.append(body.replace(cs[bad], newt, 1))
    last = m.end(3)
    n += 1
out.append(txt[last:])
open(dst, "w").write("".join(out))
print(f"ETM_FIX_DONE {dst}: {n} arcs corrected, {len(groups)} constraint groups, medians {med}")
