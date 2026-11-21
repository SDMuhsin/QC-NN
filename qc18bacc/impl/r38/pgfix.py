#!/usr/bin/env python3
"""R38: LVS source fix-up of an OpenROAD write_verilog -include_pwr_gnd netlist (read-only on the input).
   pgfix.py <in_pg.v> <cells.spi> <out.v>
 * instances of cells with no .subckt in the spice (FILL*: no devices) are dropped;
 * instances of cells whose subckt has VDD / VSS but whose statement lacks .VDD( / .VSS( get .VDD(VDD) / .VSS(VSS)
   (OpenROAD leaves filler / decap / tie / late-inserted cells without PG iterms when global_connect ran before them).
 Prints PGFIX counts per cell: dropped, patched."""
import re, sys, collections
vin, spi, vout = sys.argv[1:4]
ports = {}
for line in open(spi):
    if line[:7].lower() == '.subckt':
        t = line.split(); ports[t[1]] = set(t[2:])
drop = collections.Counter(); patch = collections.Counter(); n = 0
inst = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s+(\\\S+|[A-Za-z_][A-Za-z0-9_\[\]]*)\s*\((.*)\)\s*;\s*$', re.S)
KW = {'module', 'input', 'output', 'inout', 'wire', 'assign', 'endmodule', 'reg', 'supply0', 'supply1'}
with open(vin) as f, open(vout, 'w') as o:
    buf = ''
    for line in f:
        if not buf and (line.strip() == '' or line.split()[0] in KW or line.lstrip().startswith('//')):
            o.write(line); continue
        buf += line
        if not buf.rstrip().endswith(';'):
            continue
        m = inst.match(buf)
        if m and m.group(1) not in KW:
            cell, body = m.group(1), m.group(3); n += 1
            if cell not in ports and not cell.startswith('qb_'):
                if cell.upper().startswith('FILL'):
                    drop[cell] += 1; buf = ''; continue
            elif cell in ports:
                add = [p for p in ('VDD', 'VSS') if p in ports[cell] and '.%s(' % p not in body]
                if add:
                    patch[cell] += 1
                    extra = ', '.join('.%s(%s)' % (p, p) for p in add)
                    body = (body.strip() + ', ' + extra) if body.strip() else extra
                    buf = ' %s %s (%s);\n' % (cell, m.group(2) + (' ' if m.group(2).startswith('\\') else ''), body)
        o.write(buf); buf = ''
print('PGFIX instances %d dropped %d patched %d' % (n, sum(drop.values()), sum(patch.values())))
for c, k in sorted(drop.items()): print('PGFIX drop', c, k)
for c, k in sorted(patch.items()): print('PGFIX patch', c, k)
