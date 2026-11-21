#!/usr/bin/env python3
import re, sys
# list pins whose hold / setup constraint values exceed +-LIM, with max value; usage etmpins.py lib LIM
t = open(sys.argv[1]).read(); LIM = float(sys.argv[2])
out = []
for pm in re.finditer(r'\n\s*pin\s*\(\s*"?([^")]+)"?\s*\)\s*\{(.*?)(?=\n\s*pin\s*\(|\n\s*bus\s*\(|\Z)', t, re.S):
    pn, body = pm.group(1), pm.group(2)
    for m in re.finditer(r'timing_type\s*:\s*"?(\w+)"?\s*;(.*?)(?=\n\s*timing\s*\(|\Z)', body, re.S):
        tt, b = m.group(1), m.group(2)
        if 'hold' not in tt and 'setup' not in tt: continue
        v = [float(x) for s in re.findall(r'values\s*\((.*?)\)\s*;', b, re.S) for x in re.findall(r'-?[0-9.]+(?:e-?\d+)?', s)]
        if v and (max(v) > LIM or min(v) < -LIM): out.append((pn, tt, min(v), max(v)))
for o in out: print("ETMPIN", *o)
print("ETMPIN_N", len(out))
