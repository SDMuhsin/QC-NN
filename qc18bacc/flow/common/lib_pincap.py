#!/usr/bin/env python3
"""P&R copy of a CCS liberty whose input-pin capacitance is the one PrimeTime uses (R48, results/r48.md).
    python3 -I lib_pincap.py <in.lib> <out.lib>
OpenROAD reads the scalar pin capacitance / rise_capacitance / fall_capacitance; PrimeTime loads a net with the CCS
receiver capacitance (receiver_capacitance1/2_rise/fall tables), up to 2.7 x larger (tcbn65gplus tc median x2.08), so
OpenROAD's max-cap / max-transition repair under-fixed every high-fanout driver that PT then flagged (r48_col: OR 59 / 6
vs PT tt 1 000 / 1 165 pins).  Here every input pin's three scalar attributes become the maximum value of its receiver
capacitance tables (the tables sit in the pin's own receiver_capacitance group or in the timing groups whose related_pin
it is).  Everything else is copied unchanged.  Prints the number of pins changed and the median ratio."""
import re
import statistics
import sys

src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().split('\n')
CELL = re.compile(r'\s*cell\s*\(\s*"?([\w]+)"?\s*\)')
PIN = re.compile(r'\s*pin\s*\(\s*"?([\w]+)"?\s*\)')
REL = re.compile(r'\s*related_pin\s*:\s*"?([\w]+)"?')
NUM = re.compile(r'[0-9]*\.[0-9]+(?:[eE][+-]?\d+)?')
# pass 1: maximum receiver capacitance per (cell, input pin)
rec = {}
cell = pin = rel = None
intab = False
for s in lines:
    m = CELL.match(s)
    if m:
        cell, pin, rel = m.group(1), None, None
        continue
    m = PIN.match(s)
    if m:
        pin, rel = m.group(1), None
        continue
    m = REL.match(s)
    if m:
        rel = m.group(1)
        continue
    t = s.strip()
    if t.startswith('receiver_capacitance'):
        intab = True
        continue
    if intab:
        if t.startswith('values') or t.startswith('"'):
            v = [float(x) for x in NUM.findall(t)]
            k = (cell, rel or pin)
            if v:
                rec[k] = max(rec.get(k, 0.0), max(v))
        elif t.startswith(');'):
            intab = False
# pass 2: rewrite the scalar capacitances of input pins
out, ratios = [], []
cell = pin = None
isin = False
ATTR = re.compile(r'^(\s*)(capacitance|rise_capacitance|fall_capacitance)(\s*:\s*)([0-9.eE+-]+)(\s*;.*)$')
for s in lines:
    m = CELL.match(s)
    if m:
        cell, pin, isin = m.group(1), None, False
    m = PIN.match(s)
    if m:
        pin, isin = m.group(1), False
    if re.match(r'\s*direction\s*:\s*"?input', s):
        isin = True
    m = ATTR.match(s)
    if m and isin and (cell, pin) in rec and rec[(cell, pin)] > float(m.group(4)):
        if m.group(2) == 'capacitance':
            ratios.append(rec[(cell, pin)] / float(m.group(4)))
        s = '%s%s%s%.6f%s' % (m.group(1), m.group(2), m.group(3), rec[(cell, pin)], m.group(5))
    out.append(s)
open(dst, 'w').write('\n'.join(out))
print('LIB_PINCAP %s: %d input pins raised, median ratio %.2f' % (dst, len(ratios), statistics.median(ratios) if ratios else 0))
