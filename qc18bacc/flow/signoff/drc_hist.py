#!/usr/bin/env python3
"""Hotspot summary of an OpenROAD detailed-route DRC report (results/r5a.md): markers by type x layer, by 50-um y bin
(top bins), by x bin, and by net class (port bus / PE row / lane / BR / dec / clock / other).
   drc_hist.py <drt.drc.rpt> [ybin_um]"""
import re, sys, collections as C
f = sys.argv[1]; yb = float(sys.argv[2]) if len(sys.argv) > 2 else 50.0
tl, yh, xh, cls = C.Counter(), C.Counter(), C.Counter(), C.Counter()
n = 0; typ = srcs = None
def nclass(s):
    m = re.match(r'net:(\w+?)(\[|$)', s)
    if m and not s.startswith('net:u_core'):
        b = m.group(1)
        return 'clk' if b.startswith('clknet') else ('port:' + b if not b.startswith('net') else 'top_buf')
    m = re.search(r'g_r_(\d+)__g_c_0__', s)
    if m: return 'pe%02d' % int(m.group(1))
    if re.search(r'g_(fq|wq)_|u_pb[fw]', s): return 'lane/pbank'
    if 'u_br' in s or 'cbr' in s or 'tbr' in s: return 'br'
    if 'u_dec' in s: return 'dec'
    return 'other'
for line in open(f):
    if 'violation type' in line: typ = line.split(':', 1)[1].strip()
    elif 'srcs:' in line: srcs = line.split()[1:]
    elif 'bbox' in line:
        m = re.search(r'\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*-\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*on Layer (\S+)', line)
        if not m: continue
        x, y, lay = float(m.group(1)), float(m.group(2)), m.group(5)
        n += 1; tl[(typ, lay)] += 1; yh[int(y // yb) * yb] += 1; xh[int(x // 25) * 25] += 1
        for s in set(nclass(s) for s in (srcs or ['?'])): cls[s] += 1
print('markers', n)
print('type x layer:', ', '.join('%s/%s %d' % (t, l, c) for (t, l), c in tl.most_common(12)))
print('top y bins (um):', ', '.join('%g %d' % (k, c) for k, c in yh.most_common(12)))
print('x bins (25 um):', ', '.join('%g %d' % (k, c) for k, c in sorted(xh.items())))
print('net classes:', ', '.join('%s %d' % (k, c) for k, c in cls.most_common(14)))
