#!/usr/bin/env python3
"""R45: count ETM setup / hold tables with a value beyond median +- thr (per arc type), list the pins.
usage: etmout45.py <etm.lib> [thr_ns=2.0] [pin ...]   (pins: print their setup / hold tables' value range)"""
import sys, re, statistics, collections
lib = open(sys.argv[1]).read(); thr = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0; show = set(sys.argv[3:])
vals = collections.defaultdict(list)
for pm in re.finditer(r'pin\("([^"]+)"\) \{(.*?)\} /\* end of pin', lib, re.S):
    pin, body = pm.group(1), pm.group(2)
    for tm in re.finditer(r'timing_type : (setup|hold)_\w+ ;(.*?)end of arc', body, re.S):
        for cm in re.finditer(r'(rise|fall)_constraint.*?values \((.*?)\);', tm.group(2), re.S):
            v = [float(x) for x in re.findall(r'-?\d+\.\d+', cm.group(2))]
            vals[(tm.group(1), cm.group(1))].append((pin, min(v), max(v)))
n = 0
for k, rows in sorted(vals.items()):
    med = statistics.median([(a + b) / 2 for _, a, b in rows])
    bad = [r for r in rows if r[1] < med - thr or r[2] > med + thr]
    n += len(bad)
    print('%s %s: %d tables, median %.3f, beyond +-%.1f: %d %s' % (k[0], k[1], len(rows), med, thr, len(bad), [b[0] for b in bad[:8]]))
    for r in rows:
        if r[0] in show: print('   ', r)
print('total beyond', n)
