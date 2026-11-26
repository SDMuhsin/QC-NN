#!/usr/bin/env python3
"""IO pin geometry of an existing block abstract LEF -> floorplan pin DEF (DIEAREA + PINS, FIXED), so a re-run of the
block keeps the pin positions every neighbour was built against (the r5b_blk column that the hub / act pins were aligned
to; R35 / R48 placed the same pins with OpenROAD place_pin, R72 writes them as the DEF that flow/icc2/floorplan.tcl reads).
usage: abstract_pins.py <block.lef> <out.def>
First RECT of each signal PIN (LEF coordinates = die coordinates, origin 0 0); POWER / GROUND pins are left out (the
ICC2 floorplan makes its own PG pins).  DEF units = the LEF DATABASE MICRONS.  The LEF has no producer in this flow (it
is an input, blocks/col/col.env COL_REFLEF), so its md5 and pin counts go to the log of every run (R92)."""
import hashlib
import sys
src, dst = sys.argv[1], sys.argv[2]
pins, cur, layer, use, dirn = {}, None, None, {}, {}
macro, size, dbu = None, None, 1000
for line in open(src):
    s = line.split()
    if not s: continue
    if s[0] == 'DATABASE' and len(s) > 2: dbu = int(float(s[2])); continue
    if s[0] == 'MACRO': macro = s[1]; continue
    if s[0] == 'SIZE' and cur is None and macro: size = (float(s[1]), float(s[3])); continue
    if s[0] == 'PIN': cur = s[1]; layer = None; continue
    if cur is None: continue
    if s[0] == 'USE': use[cur] = s[1].rstrip(';')
    elif s[0] == 'DIRECTION': dirn[cur] = s[1].rstrip(';')
    elif s[0] == 'LAYER': layer = s[1]
    elif s[0] == 'RECT' and cur not in pins: pins[cur] = (layer, *map(float, s[1:5]))
    elif s[0] == 'END' and len(s) > 1 and s[1] == cur: cur = None
if not (macro and size and pins):
    sys.exit('abstract_pins: no MACRO / SIZE / PIN in %s' % src)
u = lambda v: int(round(v * dbu))
sig = [(p, g) for p, g in pins.items() if use.get(p) not in ('POWER', 'GROUND')]
with open(dst, 'w') as o:
    o.write('VERSION 5.8 ;\nDIVIDERCHAR "/" ;\nBUSBITCHARS "[]" ;\nDESIGN %s ;\nUNITS DISTANCE MICRONS %d ;\n' % (macro, dbu))
    o.write('DIEAREA ( 0 0 ) ( %d %d ) ;\nPINS %d ;\n' % (u(size[0]), u(size[1]), len(sig)))
    for p, (l, x0, y0, x1, y1) in sig:
        xc, yc = (u(x0) + u(x1)) // 2, (u(y0) + u(y1)) // 2
        o.write('- %s + NET %s + DIRECTION %s + USE SIGNAL\n  + PORT\n    + LAYER %s ( %d %d ) ( %d %d )\n'
                '    + FIXED ( %d %d ) N ;\n' % (p, p, dirn.get(p, 'INPUT'), l, u(x0) - xc, u(y0) - yc, u(x1) - xc,
                                                u(y1) - yc, xc, yc))
    o.write('END PINS\nEND DESIGN\n')
sys.stderr.write('abstract_pins: %s %d signal pins, die %g x %g, layers %s -> %s\n'
                 % (macro, len(sig), size[0], size[1], sorted({g[0] for _, g in sig}), dst))
sys.stderr.write('abstract_pins: source %s md5 %s, %d pins (%d signal, %d power / ground), %d database units / um\n'
                 % (src, hashlib.md5(open(src, 'rb').read()).hexdigest(), len(pins), len(sig), len(pins) - len(sig), dbu))
