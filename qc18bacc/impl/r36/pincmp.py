# R36 KLayout batch script: std-cell LEF pin shapes vs the cell GDS.  For every MACRO in the LEF that exists in the GDS,
# every PIN rect on M1 / M2 must lie inside that GDS cell's drawing shapes of the same layer (layer numbers from the
# KLayout map, flow gds_map.py).  Prints cells / pins whose LEF rect is not covered (R36_PINCMP lines).
#   klayout -b -r pincmp.py -rd lef=<cells.lef> -rd gds=<cells.gds> -rd map=<kl.map>
import re
import pya

lay = {}
for line in open(map):
    t = line.split()
    if len(t) == 4 and t[0] in ('M1', 'M2', 'M3') and 'NET' in t[1]:
        lay[t[0]] = (int(t[2]), int(t[3]))
ly = pya.Layout(); ly.read(gds)
dbu = ly.dbu
li = {k: ly.layer(*v) for k, v in lay.items()}
txt = open(lef).read()
bad = 0; cells = 0; pins = 0; badcells = {}
for m in re.finditer(r'\nMACRO (\S+)(.*?)\nEND \1', txt, re.S):
    name, body = m.group(1), m.group(2)
    c = ly.cell(name)
    if c is None:
        continue
    cells += 1
    reg = {k: pya.Region(c.begin_shapes_rec(l)) for k, l in li.items()}
    for pm in re.finditer(r'\n\s*PIN (\S+)(.*?)\n\s*END \1', body, re.S):
        pn = pm.group(1)
        if pn in ('VDD', 'VSS'):
            continue
        layer = None
        for line in pm.group(2).split('\n'):
            s = line.split()
            if s[:1] == ['LAYER']:
                layer = s[1]
            elif s[:1] == ['RECT'] and layer in reg:
                x0, y0, x1, y1 = [float(v) for v in s[1:5]]
                pins += 1
                b = pya.Region(pya.Box(int(round(x0 / dbu)), int(round(y0 / dbu)), int(round(x1 / dbu)), int(round(y1 / dbu))))
                if not (b - reg[layer]).is_empty():
                    bad += 1; badcells.setdefault(name, set()).add(pn)
print('R36_PINCMP cells %d pin_rects %d not_covered %d cells_with_bad_pins %d' % (cells, pins, bad, len(badcells)))
for k in sorted(badcells)[:60]:
    print('R36_PINCMP_BAD %s %s' % (k, ' '.join(sorted(badcells[k]))))
