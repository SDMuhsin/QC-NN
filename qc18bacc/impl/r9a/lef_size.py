#!/usr/bin/env python3
"""R9a: set the abstract LEF's SIZE to the die (QB9_DIE line of abs.log) and ORIGIN to 0 0, in place.
usage: lef_size.py <block.lef> <abs.log>"""
import re, sys
lef, log = sys.argv[1], sys.argv[2]
m = re.search(r'QB9_DIE ([0-9.]+) ([0-9.]+)', open(log).read())
W, H = m.group(1), m.group(2)
t = open(lef).read()
old = re.search(r'^\s*SIZE .*;$', t, re.M).group(0)
t = re.sub(r'^(\s*)SIZE .*;$', r'\g<1>SIZE %s BY %s ;' % (W, H), t, count=1, flags=re.M)
t = re.sub(r'^(\s*)ORIGIN .*;$', r'\g<1>ORIGIN 0 0 ;', t, count=1, flags=re.M)
open(lef, 'w').write(t)
print('lef_size: %s -> SIZE %s BY %s' % (old.strip(), W, H))
