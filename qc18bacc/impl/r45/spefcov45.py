#!/usr/bin/env python3
"""R45 probe: nets of a flat routed Verilog netlist that have no *D_NET in the SPEF (PrimeTime 'not annotated').
usage: spefcov45.py <netlist.v> <spef>   -> counts by name class + examples"""
import sys, re, collections
v = open(sys.argv[1]).read()
nets = set()
for m in re.finditer(r'\.\w+\(\s*(\\\S+\s|[^\s\(\)]+)\s*\)', v):
    n = m.group(1).strip()
    if n.startswith('\\'): n = n[1:]
    nets.add(n)
sp = set()
with open(sys.argv[2]) as f:
    for line in f:
        if line.startswith('*D_NET'):
            sp.add(line.split()[1].replace('\\', ''))
miss = sorted(n for n in nets if n not in sp and not n.startswith("1'b"))
cls = collections.Counter(re.sub(r'\d+', 'N', n.split('/')[0])[:40] for n in miss)
print('netlist nets', len(nets), 'spef nets', len(sp), 'netlist nets without D_NET', len(miss))
for k, c in cls.most_common(15): print('  %6d %s' % (c, k))
print('examples', miss[:10])
