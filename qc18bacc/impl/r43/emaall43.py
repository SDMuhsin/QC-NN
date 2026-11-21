#!/usr/bin/env python3
"""R43: netlist for impl/r43/ema43.tcl variant 'all': every signal pin of one qb_w connected (inputs to their own TIEL,
outputs to a BUFFD1 input) - full pin-access test of a macro PDN variant.  usage: emaall43.py <macro.lef> <out.v>"""
import re, sys
cur = None; d = {}
for l in open(sys.argv[1]):
    m = re.match(r'\s*PIN\s+(\S+)', l)
    if m: cur = m.group(1); continue
    m = re.match(r'\s*DIRECTION\s+(\S+)', l)
    if m and cur: d[cur] = m.group(1)
    m = re.match(r'\s*USE\s+(\S+)', l)
    if m and cur and m.group(1) in ('POWER', 'GROUND'): d.pop(cur, None)
buses = {}
for p, io in d.items():
    m = re.match(r'(.*)\[(\d+)\]$', p)
    b, i = (m.group(1), int(m.group(2))) if m else (p, None)
    buses.setdefault(b, {})[i] = io
w, conn, cells = [], [], []
k = 0
for b, bits in sorted(buses.items()):
    nets = []
    for i in sorted(bits, key=lambda x: -1 if x is None else x)[::-1]:
        k += 1; n = f"n{k}"; w.append(n); nets.append(n)
        if bits[i] == 'INPUT': cells.append(f"TIEL t{k}(.ZN({n}));")
        else: cells.append(f"BUFFD1 b{k}(.I({n}), .Z());")
    conn.append(f".{b}({{{','.join(nets)}}})" if None not in bits else f".{b}({nets[0]})")
open(sys.argv[2], 'w').write("module t();\nwire " + ",".join(w) + ";\n" + "\n".join(cells) + f"\nqb_w_204x144m2 m({', '.join(conn)});\nendmodule\n")
print("EMAALL nets", k)
