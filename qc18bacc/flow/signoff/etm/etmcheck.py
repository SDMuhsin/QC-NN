#!/usr/bin/env python3
"""R35 (results/r35a.md bug 1): sanity scan of a block ETM .lib - input pin capacitance (max / count above CAP fF),
the largest index_1 (input transition) of the constraint tables, and setup / hold / clk->out values outside +-LIM ns.
R64 (results/r64.md): input pins' max_transition (min / max); exit 1 if an input pin has none or 0 (R63: the ETM context
set_input_transition 0 gave max_transition 0 on all 6958 data inputs, signoff/pt/common.tcl qb_etm_inputs).
usage: etmcheck.py <etm.lib> [LIM=3.0] [CAP=0.065]"""
import re, sys
src = sys.argv[1]; LIM = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0; CAP = float(sys.argv[3]) if len(sys.argv) > 3 else 0.065
t = open(src).read()
caps = [float(x) for x in re.findall(r'\n\s*capacitance\s*:\s*([0-9.eE+-]+)', t)]
bad = {}; idx = []; vals = {}
for m in re.finditer(r'timing_type\s*:\s*"?(\w+)"?\s*;(.*?)(?=\n\s*timing\s*\(|\n\s*pin\s*\(|\Z)', t, re.S):
    tt, body = m.group(1), m.group(2)
    k = 'setup' if 'setup' in tt else 'hold' if 'hold' in tt else 'removal' if 'removal' in tt else 'recovery' if 'recovery' in tt else 'arc'
    for i1 in re.findall(r'index_1\s*\(\s*"([^"]*)"', body):
        idx.append(max(float(x) for x in i1.split(',')))
    for v in re.findall(r'values\s*\((.*?)\)\s*;', body, re.S):
        for x in re.findall(r'[-0-9.eE+]+', v):
            try: x = float(x)
            except ValueError: continue
            vals.setdefault(k, []).append(x)
            if abs(x) > LIM: bad[k] = bad.get(k, 0) + 1
print('ETMCHECK %s pins_cap max %.4f pF, > %.3f: %d of %d' % (src, max(caps) if caps else 0, CAP, sum(c > CAP for c in caps), len(caps)))
print('ETMCHECK max table input transition %.3f ns' % (max(idx) if idx else 0))
for k, v in sorted(vals.items()):
    print('ETMCHECK %-8s n %7d min %8.3f max %8.3f  beyond +-%.1f: %d' % (k, len(v), min(v), max(v), LIM, bad.get(k, 0)))
mt = {}
for m in re.finditer(r'\n\s*pin\s*\(\s*"?([^")]+)"?\s*\)\s*\{(.*?)(?=\n\s*(?:pin|bus)\s*\(|\Z)', t, re.S):
    body = m.group(2)
    if re.search(r'^\s*direction\s*:\s*"?input', body, re.M):
        v = re.search(r'^\s*max_transition\s*:\s*([0-9.eE+-]+)', body, re.M)
        mt[m.group(1)] = float(v.group(1)) if v else 0.0
z = sorted(p for p, v in mt.items() if v <= 0)
print('ETMCHECK input pins %d max_transition min %.4f max %.4f, missing or 0: %d %s' % (len(mt), min(mt.values()) if mt else 0,
      max(mt.values()) if mt else 0, len(z), ' '.join(z[:3])))
sys.exit(1 if z or not mt else 0)
