#!/usr/bin/env python3
"""R28: DR marker classification.  an28.py <mk28 dump> <drt.drc.rpt> [layer M2]
Per type x layer counts; for markers of type Short on <layer>: source class (2 signal nets / with VDD|VSS / 1 source /
other), master under the marker centre (markers per instance and per 1k signal pins of that master, top 15), the
marker centre's y offset in its row (0.1 um bins) and x offset to the M2/M3 vertical track grid.  Aggregates only."""
import sys, re, collections as C, bisect
dump, rpt = sys.argv[1], sys.argv[2]
LAY = sys.argv[3] if len(sys.argv) > 3 else 'M2'
ry0 = rh = None; pitch = {}; inst = []
for l in open(dump):
    t = l.split()
    if t[0] == 'ROW': ry0, rh = float(t[1]), float(t[2])
    elif t[0] == 'PITCH': pitch.setdefault((t[1], t[2]), (float(t[3]), float(t[4])))
    else: inst.append((t[0], float(t[1]), float(t[2]), float(t[3]), float(t[4]), int(t[5])))
nm, sp = C.Counter(), C.Counter()
rows = C.defaultdict(list)                     # row index -> sorted (x0, x1, master)
for m, x0, y0, x1, y1, ns in inst:
    nm[m] += 1; sp[m] += ns
    for k in range(int(round((y0 - ry0) / rh)), int(round((y1 - ry0) / rh))):
        rows[k].append((x0, x1, m))
for k in rows: rows[k].sort()
xs = {k: [a[0] for a in v] for k, v in rows.items()}
def master_at(x, y):
    k = int((y - ry0) // rh); v = rows.get(k)
    if not v: return '(none)'
    i = bisect.bisect_right(xs[k], x) - 1
    return v[i][2] if i >= 0 and v[i][0] <= x <= v[i][1] else '(gap)'
TL, src, mas, yoff, xoff = C.Counter(), C.Counter(), C.Counter(), C.Counter(), C.Counter()
typ = srcs = None; n = 0
for l in open(rpt):
    l = l.strip()
    if l.startswith('violation type:'): typ = l.split(':', 1)[1].strip()
    elif l.startswith('srcs:'): srcs = l.split()[1:]
    elif l.startswith('bbox'):
        m = re.match(r'bbox = \( *([-\d.]+), *([-\d.]+) *\) - \( *([-\d.]+), *([-\d.]+) *\) on Layer (\S+)', l)
        x = (float(m.group(1)) + float(m.group(3))) / 2; y = (float(m.group(2)) + float(m.group(4))) / 2; L = m.group(5)
        TL[(typ, L)] += 1
        if typ == 'Short' and L == LAY:
            n += 1
            ss = [s.split(':', 1)[0] + (':PG' if s.split(':', 1)[1] in ('VDD', 'VSS') else '') for s in srcs]
            src[' '.join(sorted(ss))] += 1
            mas[master_at(x, y)] += 1
            yoff['%.1f' % ((y - ry0) % rh)] += 1
            for d in ('X',):
                if ('M3', d) in pitch:
                    o, p = pitch[('M3', d)]; xoff['%.2f' % (round(((x - o) % p) / 0.01) * 0.01 % p)] += 1
print('AN28 markers by type/layer (top 12):', ', '.join('%s/%s %d' % (a, b, c) for (a, b), c in TL.most_common(12)))
print('AN28 %s shorts %d; sources:' % (LAY, n), ', '.join('%s %d (%.1f %%)' % (k, v, 100.0 * v / n) for k, v in src.most_common(6)))
print('AN28 master under marker (markers, %%, per inst, per 1k sig pins, inst count):')
for k, v in mas.most_common(15):
    print('  %-14s %7d %5.1f %%  %.3f  %6.1f  %d' % (k, v, 100.0 * v / n, v / nm[k] if nm[k] else 0, 1000.0 * v / sp[k] if sp[k] else 0, nm[k]))
tot_p = sum(sp.values()); print('AN28 all: %d insts, %d sig pins, %.1f markers per 1k pins' % (len(inst), tot_p, 1000.0 * n / tot_p))
print('AN28 y offset in row (um: count):', ' '.join('%s:%d' % (k, yoff[k]) for k in sorted(yoff, key=float)))
print('AN28 x offset to M3 track grid (um, top 8):', ' '.join('%s:%d' % kv for kv in xoff.most_common(8)), 'M3 grid', pitch.get(('M3', 'X')))
