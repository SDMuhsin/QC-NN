#!/usr/bin/env python3
"""Pin-only abstract LEF of a block with no reference abstract (the regression block blocks/rgr): the top module's ports
of a DC netlist, inputs on the west edge, outputs on the east edge, each a <w> x <d> um rectangle on the horizontal
routing layer <layer> touching the die edge, centred on that layer's track y = <offset> + k <pitch>, <step> tracks
apart, the column centred on the die.  floorplan/abstract_pins.py turns it into the floorplan pin DEF (the same path as
the column's reference abstract, blocks/col).
usage: edge_pins.py <netlist.v> <top> <die_w> <die_h> <layer> <pitch> <offset> <w> <d> <step> <out.lef>"""
import re
import sys
if len(sys.argv) != 12:
    sys.exit(__doc__)
nl, top, out = sys.argv[1], sys.argv[2], sys.argv[11]
dw, dh, pitch, off, w, dep = map(float, (sys.argv[3], sys.argv[4], sys.argv[6], sys.argv[7], sys.argv[8], sys.argv[9]))
layer, step = sys.argv[5], int(sys.argv[10])
text = open(nl).read()
m = re.search(r'\bmodule\s+%s\b(.*?)\bendmodule\b' % re.escape(top), text, re.S)
if not m:
    sys.exit('edge_pins: no module %s in %s' % (top, nl))
ports = {'INPUT': [], 'OUTPUT': []}
for d, msb, lsb, names in re.findall(r'\b(input|output)\s+(?:\[(\d+):(\d+)\]\s*)?([^;]+);', m.group(1)):
    for n in (x.strip() for x in names.split(',')):
        # both bus directions: [7:0] and [0:7] (R102: range(lsb, msb + 1) was empty for an ascending bus, no pins)
        if msb == '':
            ports[d.upper()].append(n)
        else:
            lo, hi = sorted((int(msb), int(lsb)))
            ports[d.upper()].extend('%s[%d]' % (n, i) for i in range(lo, hi + 1))
if not ports['INPUT'] or not ports['OUTPUT']:
    sys.exit('edge_pins: %s has %d inputs, %d outputs' % (top, len(ports['INPUT']), len(ports['OUTPUT'])))
ntrk = int((dh - off) / pitch) + 1
with open(out, 'w') as o:
    o.write('VERSION 5.8 ;\nBUSBITCHARS "[]" ;\nDIVIDERCHAR "/" ;\nUNITS\n  DATABASE MICRONS 1000 ;\nEND UNITS\n')
    o.write('MACRO %s\n  CLASS BLOCK ;\n  ORIGIN 0 0 ;\n  SIZE %.3f BY %.3f ;\n' % (top, dw, dh))
    for d, x0, x1 in (('INPUT', 0.0, dep), ('OUTPUT', dw - dep, dw)):
        k0 = (ntrk - (len(ports[d]) - 1) * step) // 2
        if k0 < 1:
            sys.exit('edge_pins: %d %s pins, %d tracks apart, do not fit %d tracks' % (len(ports[d]), d, step, ntrk))
        for i, p in enumerate(ports[d]):
            y = off + (k0 + i * step) * pitch
            o.write('  PIN %s\n    DIRECTION %s ;\n    USE %s ;\n    PORT\n      LAYER %s ;\n        RECT %.3f %.3f %.3f %.3f ;\n'
                    '    END\n  END %s\n' % (p, d, 'CLOCK' if p == 'clk' else 'SIGNAL', layer, x0, y - w / 2, x1, y + w / 2, p))
    o.write('END %s\nEND LIBRARY\n' % top)
sys.stderr.write('edge_pins: %s %d inputs (west) %d outputs (east) on %s every %g um -> %s\n'
                 % (top, len(ports['INPUT']), len(ports['OUTPUT']), layer, step * pitch, out))
