#!/usr/bin/env python3
"""R38: LVS black-box stubs for macros that have no layout / netlist (front-end-licensed SRAMs).
   lefstub.py <out.spi> <out.box> <macro.lef> [...]
 out.spi: one empty .SUBCKT per LEF MACRO (pins sorted by bus name / index); out.v (same stem): Verilog module stubs with
 bus ranges for v2lvs -l; out.box: 'LVS BOX <macro>' deck lines."""
import sys, re, collections
spi, box, lefs = sys.argv[1], sys.argv[2], sys.argv[3:]
vout = re.sub(r'\.spi$', '', spi) + '.v'
with open(spi, 'w') as o, open(box, 'w') as b, open(vout, 'w') as v:
    o.write('*.BUSDELIMITER [\n')
    for lef in lefs:
        mac = None; pins = []; cur = None; dirs = {}
        for line in open(lef):
            t = line.split()
            if t[:1] == ['MACRO']: mac = t[1]; pins = []
            elif t[:1] == ['PIN'] and mac: cur = t[1]; pins.append(cur)
            elif t[:1] == ['DIRECTION'] and cur: dirs[cur] = t[1].lower()
            elif t[:1] == ['END'] and len(t) > 1 and t[1] == mac:
                bus = collections.OrderedDict()
                for p in pins:
                    m = re.match(r'(.*)\[(\d+)\]$', p)
                    k = m.group(1) if m else p
                    bus.setdefault(k, []).append(int(m.group(2)) if m else None)
                flat = []
                for k, ix in bus.items():
                    flat += ['%s[%d]' % (k, i) for i in sorted(ix, reverse=True)] if ix[0] is not None else [k]
                o.write('.SUBCKT %s %s\n.ENDS\n' % (mac, ' '.join(flat)))
                decl = []
                for k, ix in bus.items():
                    d = {'input': 'input', 'output': 'output'}.get(dirs.get(k + ('[%d]' % ix[0] if ix[0] is not None else ''), 'inout'), 'inout')
                    decl.append('  %s %s%s;' % (d, '[%d:%d] ' % (max(ix), min(ix)) if ix[0] is not None else '', k))
                v.write('module %s (%s);\n%s\nendmodule\n' % (mac, ', '.join(bus), '\n'.join(decl)))
                b.write('LVS BOX %s\n' % mac); print('LEFSTUB', mac, len(pins), 'pins', len(bus), 'ports'); mac = None; cur = None
