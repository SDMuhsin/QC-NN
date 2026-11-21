#!/usr/bin/env python3
"""R45 probe: count VIA12 immediately followed by VIA23 at the same point (M2 = via pads only, unless a patch / wire
touches it), and M2 RECT patches.  usage: stack45.py <def>"""
import sys, re
txt = open(sys.argv[1]).read()
a = txt.find('\nNETS '); b = txt.find('END NETS', a)
tok = re.findall(r'\(\s*[^)]*\)|[A-Za-z_][\w\[\]]*|;', txt[a:b])
st = v12 = rect = 0; prev = None
for t in tok:
    if t.startswith('VIA12'): v12 += 1
    if t.startswith('VIA23') and prev and prev.startswith('VIA12'): st += 1
    if t.startswith('VIA12') and prev and prev.startswith('VIA23'): st += 1
    if t == 'RECT' and lay == 'M2': rect += 1
    if re.match(r'M\d$', t): lay = t
    prev = t
print('VIA12', v12, 'VIA12/VIA23 stacked pairs', st, 'M2 RECT patches', rect)
