#!/usr/bin/env python3
"""ASCII map of gr_diag.tcl TILE lines: utilisation class and dominant block per 50-um tile."""
import sys, re
t = {}
for l in open(sys.argv[1]):
    m = re.match(r"TILE x\s+(\d+) y\s+(\d+) util (\S+) top (\S+)\s+(\S+)", l)
    if m: t[int(m[1]), int(m[2])] = (float(m[3]), m[4])
xs = sorted({k[0] for k in t}); ys = sorted({k[1] for k in t}, reverse=True)
def cu(u): return '.' if u < 0.7 else 'o' if u < 0.85 else 'O' if u < 0.95 else '#'
def cb(b):
    if b.startswith('u_array'): return 'p'
    return {'u_xbar': 'X', 'u_act': 'A', 'u_head': 'H', 'u_agu': 'G', 'u_seq': 'S', 'u_drain': 'D', 'top': 't',
            'u_host': 'h', 'u_wmem_e': 'W', 'u_wmem_o': 'W', 'u_pmem': 'M', 'u_desc': 'd'}.get(b, 'P' if 'ppu' in b else '?')
x0, x1 = min(xs), max(xs)
for y in ys:
    a = ''.join(cu(t[x, y][0]) if (x, y) in t else ' ' for x in range(x0, x1 + 50, 50))
    b = ''.join(cb(t[x, y][1]) if (x, y) in t else ' ' for x in range(x0, x1 + 50, 50))
    print(f"{y:5d} {a}   {b}")
