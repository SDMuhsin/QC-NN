#!/usr/bin/env python3
"""R45 probe: ICG (CKLNQD*) enable nets in a routed DEF: driver -> ICG distance and net HPWL, vs the PT max_transition
report (optional).  usage: icge45.py <def> [pt_drv.rpt]"""
import sys, re, collections
deff = sys.argv[1]
txt = open(deff).read(); u = int(re.search(r'UNITS DISTANCE MICRONS (\d+)', txt).group(1))
a = txt.index('\nCOMPONENTS'); b = txt.index('END COMPONENTS', a)
pos, mast = {}, {}
for m in re.finditer(r'-\s+(\S+)\s+(\S+)\s+[^;]*?(?:PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)', txt[a:b]):
    pos[m.group(1)] = (int(m.group(3)) / u, int(m.group(4)) / u); mast[m.group(1)] = m.group(2)
icg = {i for i, mm in mast.items() if mm.startswith('CKLNQD')}
slew = {}
if len(sys.argv) > 2:
    for line in open(sys.argv[2]):
        t = line.split()
        if len(t) >= 4 and 'VIOLATED' in line and t[0].endswith('/E'):
            slew[t[0][:-2]] = float(t[2])
a = txt.index('\nNETS'); b = txt.index('END NETS', a)
rows = []
for stmt in txt[a:b].split(';'):
    head = stmt.split('+')[0]
    conns = re.findall(r'\(\s*(\S+)\s+(\S+)\s*\)', head)
    ic = [c for c in conns if c[1] == 'E' and c[0] in icg]
    if not ic: continue
    pts = [pos[c[0]] for c in conns if c[0] in pos]
    hp = (max(p[0] for p in pts) - min(p[0] for p in pts)) + (max(p[1] for p in pts) - min(p[1] for p in pts)) if pts else 0
    for c in ic:
        name = c[0].replace('\\', '')
        rows.append((hp, len(conns), name, slew.get(name)))
rows.sort(reverse=True)
hps = sorted(r[0] for r in rows)
print('ICG enable nets', len(rows), 'HPWL p50 %.0f p90 %.0f max %.0f um' % (hps[len(hps) // 2], hps[int(len(hps) * 0.9)], hps[-1]))
v = [r for r in rows if r[3] is not None]
print('with PT slew violation at E', len(v), '; their HPWL p50 %.0f um' % (sorted(r[0] for r in v)[len(v) // 2] if v else 0))
for r in rows[:12]: print('  HPWL %.0f um, %d pins, %s, PT E slew %s' % r)
