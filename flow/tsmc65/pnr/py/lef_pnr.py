#!/usr/bin/env python3
"""Router copy of the tech LEF (stays in the build directory):  lef_pnr.py <in.lef> <out.lef> <layer> [...]
Drops the MINIMUMCUT statements of the listed routing layers.  Reason: on tcbn65gplus most output pins are M1
shapes >= 0.3 um wide, M1 has 'MINIMUMCUT 2 WIDTH 0.300' and the OpenROAD detailed router's pin access only
uses single-cut vias, so those pins get no access point (DRT-0073).  The routed result can then contain
single-cut VIA1 on wide M1 pins, which sign-off DRC flags (see pnr/README.md)."""
import sys

src, dst, layers = sys.argv[1], sys.argv[2], set(sys.argv[3:])
cur, dropped, out = None, 0, []
for line in open(src):
    t = line.split()
    if len(t) == 2 and t[0] == 'LAYER':
        cur = t[1]
    elif len(t) >= 2 and t[0] == 'END' and t[1] == cur:
        cur = None
    if cur in layers and t[:1] == ['MINIMUMCUT']:
        dropped += 1
        continue
    out.append(line)
open(dst, 'w').write(''.join(out))
print('lef_pnr: dropped %d MINIMUMCUT rules on %s' % (dropped, ' '.join(sorted(layers))))
