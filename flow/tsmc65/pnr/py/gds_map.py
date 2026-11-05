#!/usr/bin/env python3
"""KLayout LEF/DEF layer map from a Virtuoso stream map:  gds_map.py <virtuoso.map> <tech.lef> <out.map>
Routing / cut layers of the LEF get the 'drawing' layer/datatype for wires, vias and pins, their 'pin' purpose
for pin labels; the die area goes to prBoundary."""
import sys

vmap, lef, out = sys.argv[1:4]
m = {}
for line in open(vmap):
    t = line.split()
    if len(t) >= 4 and not t[0].startswith('#') and t[2].isdigit() and t[3].isdigit():
        m.setdefault((t[0], t[1]), (t[2], t[3]))
layers = []
for line in open(lef):
    t = line.split()
    if t[:1] == ['MACRO']:
        break
    if len(t) == 2 and t[0] == 'LAYER':
        layers.append(t[1])
rows = []
for l in layers:
    if (l, 'drawing') in m:
        rows.append('%s NET,SPNET,VIA,PIN,LEFPIN,LEFOBS,FILL,VIAFILL %s %s' % ((l,) + m[(l, 'drawing')]))
    if (l, 'pin') in m:
        rows.append('NAME %s/PIN,%s/LEFPIN %s %s' % ((l, l) + m[(l, 'pin')]))
if ('prBoundary', 'drawing') in m:
    rows.append('DIEAREA ALL %s %s' % m[('prBoundary', 'drawing')])
open(out, 'w').write('\n'.join(rows) + '\n')
print('gds_map: %d entries' % len(rows))
