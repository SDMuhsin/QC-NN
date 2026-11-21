#!/usr/bin/env python3
"""R45: router LEF with the kit's LEF57_* layer properties written as native LEF 5.7 statements (VERSION 5.7), so
OpenROAD reads them as rules: LEF57_SPACING "SPACING .. ENDOFLINE .." (ignored as a property: ODB-0388) and
LEF57_MINSTEP "MINSTEP l MAXEDGES n" (read only as a LEF58 min-step rule, which DRT does not check in this build).
usage: lef57n45.py <in.lef> <out.lef> [drop-MINIMUMCUT layers...] [ALLLAYERS]
Routing layers only by default: the cut-layer LEF57_SPACING PARALLELOVERLAP, made native, changes pdngen via arrays
(VIA5/VIA6 4 x 0.40 -> 3 x 0.46 um pitch: Calibre VIA6.R.2 on the M4-M7 stacks, R45 test v2)."""
import sys, re
src, dst, drop = sys.argv[1], sys.argv[2], set(sys.argv[3:])
ALL = 'ALLLAYERS' in drop; drop.discard('ALLLAYERS'); typ = None
out, cur, n = [], None, {'spacing': 0, 'minstep': 0, 'mincut': 0}
for line in open(src):
    t = line.split()
    if len(t) == 2 and t[0] == 'LAYER': cur = t[1]; typ = None
    if cur and t[:1] == ['TYPE']: typ = t[1]
    elif len(t) >= 2 and t[0] == 'END' and t[1] == cur: cur = None
    if t[:2] == ['VERSION', '5.6']:
        line = 'VERSION 5.7 ;\n'
    m = re.match(r'\s*PROPERTY\s+LEF57_(SPACING|MINSTEP)\s+"(.*)"\s*;', line)
    if m and cur and (typ == 'ROUTING' or ALL):
        n[m.group(1).lower()] += 1
        line = '    %s\n' % m.group(2).strip()
    if cur in drop and t[:1] == ['MINIMUMCUT']:
        n['mincut'] += 1; continue
    out.append(line)
open(dst, 'w').write(''.join(out))
print('lef57n45: native', n['spacing'], 'SPACING /', n['minstep'], 'MINSTEP; dropped', n['mincut'], 'MINIMUMCUT on', sorted(drop))
