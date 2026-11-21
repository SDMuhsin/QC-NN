#!/usr/bin/env python3
"""R45 probe: DEF routing elements (regular + special nets) near a point.  usage: defat45.py <def> x_um y_um [r_um=0.3]"""
import sys, re
deff, x, y = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]); r = float(sys.argv[4]) if len(sys.argv) > 4 else 0.3
txt = open(deff).read(); u = int(re.search(r'UNITS DISTANCE MICRONS (\d+)', txt).group(1))
for sec in ('SPECIALNETS', 'NETS'):
    a = txt.find('\n%s ' % sec); b = txt.find('END %s' % sec, a)
    if a < 0: continue
    for stmt in txt[a:b].split(';'):
        name = re.search(r'-\s+(\S+)', stmt)
        for m in re.finditer(r'(?:ROUTED|NEW|FIXED|COVER)\s+(M\d)\s+(\d+\s+)?(?:\+ SHAPE \S+\s+)?\(\s*(-?\d+)\s+(-?\d+)[^)]*\)\s*(\(\s*(\S+)\s+(\S+)[^)]*\))?\s*(\S+)?', stmt):
            px, py = int(m.group(3)) / u, int(m.group(4)) / u
            qx = px if not m.group(6) or m.group(6) == '*' else int(m.group(6)) / u
            qy = py if not m.group(7) or m.group(7) == '*' else int(m.group(7)) / u
            if min(px, qx) - r <= x <= max(px, qx) + r and min(py, qy) - r <= y <= max(py, qy) + r:
                print(sec, name.group(1) if name else '?', m.group(0).strip()[:120])
