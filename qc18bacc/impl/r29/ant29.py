#!/usr/bin/env python3
# R29 (results/r29.md): antenna root-cause measurement of a routed hub (aggregates only).
#   python3 -I ant29.py <run_dir> [antenna_rpt]   reads kit.env (LEF / MACRO_LEFS), out/qb_hub.def, route.guide,
#   rpt/antenna.rpt; prints per-violation and population statistics (no kit data, only numbers).
import sys, re, os, collections, statistics as st
d = sys.argv[1]; rpt = sys.argv[2] if len(sys.argv) > 2 else d + '/rpt/antenna.rpt'
env = dict(re.findall(r'^(\w+)="(.*)"', open(d + '/kit.env').read(), re.M))
lefs = [env['LEF']] + env['MACRO_LEFS'].split()
# ---- LEF pins: direction, gate area, diff area, port layers
pins = {}  # (cell,pin) -> dict
for f in lefs:
    cell = pin = None
    for ln in open(f, errors='ignore'):
        t = ln.split()
        if not t: continue
        if t[0] == 'MACRO': cell = t[1]
        elif t[0] == 'PIN' and cell: pin = t[1]; pins[(cell, pin)] = {'dir': '', 'g': 0.0, 'df': 0.0, 'lay': set()}
        elif t[0] == 'END' and len(t) > 1 and t[1] == pin: pin = None
        elif pin:
            p = pins[(cell, pin)]
            if t[0] == 'DIRECTION': p['dir'] = t[1]
            elif t[0] == 'ANTENNAGATEAREA': p['g'] += float(t[1])
            elif t[0] == 'ANTENNADIFFAREA': p['df'] = max(p['df'], float(t[1]))
            elif t[0] == 'LAYER': p['lay'].add(t[1])
macros = set(c for f in lefs[1:] for c in re.findall(r'^MACRO (\S+)', open(f).read(), re.M))
# ---- antenna report: net -> [(inst, pin, cell, layer, ratio)]
viol = collections.defaultdict(list); net = pin = lay = None
for ln in open(rpt):
    m = re.match(r'Net: (\S+)', ln)
    if m: net = m.group(1); continue
    m = re.match(r'\s+Pin: (\S+)/(\S+) \((\S+)\)', ln)
    if m: pin = m.groups(); continue
    m = re.match(r'\s+Layer: (\S+)', ln)
    if m: lay = m.group(1); continue
    m = re.match(r'\s+Cumulative area ratio: (\S+)', ln)
    if m:
        viol[net].append((pin[0], pin[1], pin[2], lay, float(m.group(1))))
# ---- DEF
comp = {}; nets = {}; U = 2000.0
LAY = ['M1','M2','M3','M4','M5','M6','M7','M8','M9']
sec = None; cur = None; buf = []
def seglen(rec):
    L = collections.Counter(); last = None
    for part in re.split(r'\+ ROUTED|NEW', rec)[1:]:
        tk = part.replace('(', ' ( ').replace(')', ' ) ').split()
        if not tk or tk[0] not in LAY: continue
        lay = tk[0]; pts = []; i = 1
        while i < len(tk):
            if tk[i] == '(':
                j = tk.index(')', i); v = tk[i+1:j]
                if 'RECT' in tk[max(0,i-1):i]: break
                x = v[0]; y = v[1]
                if pts:
                    x = pts[-1][0] if x == '*' else float(x); y = pts[-1][1] if y == '*' else float(y)
                else: x = float(x); y = float(y)
                pts.append((x, y)); i = j + 1
            elif tk[i] == 'RECT': break
            else: i += 1
        for a, b in zip(pts, pts[1:]): L[lay] += (abs(a[0]-b[0]) + abs(a[1]-b[1])) / U
    return L
def fin(rec):
    m = re.match(r'\s*- (\S+)', rec); n = m.group(1)
    head = rec.split('+')[0]
    ps = re.findall(r'\( (\S+) (\S+) \)', head)
    nets[n] = (ps, seglen(rec) if n in viol or keep(ps) else None)
def keep(ps):  # population control: nets with a macro input sink, or nets driven by a macro
    return any(i != 'PIN' and comp.get(i, ('',))[0] in macros for i, _ in ps)
with open(d + '/out/qb_hub.def') as fh:
    for ln in fh:
        if ln.startswith('COMPONENTS'): sec = 'C'; continue
        if ln.startswith('END COMPONENTS'): sec = None; continue
        if ln.startswith('NETS'): sec = 'N'; continue
        if ln.startswith('END NETS'):
            if buf: fin(''.join(buf))
            break
        if sec == 'C':
            m = re.match(r'\s*- (\S+) (\S+) .*\( (-?\d+) (-?\d+) \)', ln)
            if m: comp[m.group(1)] = (m.group(2), int(m.group(3)) / U, int(m.group(4)) / U)
        elif sec == 'N':
            if re.match(r'\s*- ', ln):
                if buf: fin(''.join(buf))
                buf = [ln]
            else: buf.append(ln)
# ---- guides for violating nets
gl = collections.defaultdict(collections.Counter); g = None
with open(d + '/route.guide') as fh:
    for ln in fh:
        t = ln.split()
        if len(t) == 1 and t[0] not in '()': g = t[0] if t[0] in viol else None
        elif g and len(t) == 5:
            x0, y0, x1, y1 = map(float, t[:4]); gl[g][t[4]] += max(x1-x0, y1-y0) / U
def drv(ps):
    for i, p in ps:
        if i == 'PIN': continue
        c = comp[i][0]; q = pins.get((c, p), {})
        if q.get('dir') == 'OUTPUT': return i, p, c
    return None
def q(v, k=(0.1, 0.5, 0.9)):
    v = sorted(v); return ' '.join('%.0f' % v[min(len(v)-1, int(x*len(v)))] for x in k) if v else '-'
# ---- report
print('violating nets', len(viol), 'pins', sum(len(set((a,b) for a,b,*_ in v)) for v in viol.values()))
sink = collections.Counter(); vlay = collections.Counter(); drvt = collections.Counter(); sinklay = collections.Counter()
tot = []; dist = []; frac = collections.Counter(); hi = []; glay = collections.Counter(); rlay = collections.Counter(); fan = []
for n, vs in viol.items():
    ps, L = nets[n]; dv = drv(ps)
    drvt['macro' if dv and dv[2] in macros else ('PIN' if dv is None else 'std')] += 1
    fan.append(len(ps) - 1)
    for i, p, c, lay, r in {(a, b, c, l, r) for a, b, c, l, r in vs}:
        pass
    seen = set()
    for i, p, c, lay, r in vs:
        vlay[lay] += 1
        if (i, p) in seen: continue
        seen.add((i, p)); sink['macro:' + c[:4] if c in macros else c] += 1
        sinklay[','.join(sorted(pins.get((c, p), {}).get('lay', [])))] += 1
        if dv: x = comp[i]; y = comp[dv[0]]; dist.append(abs(x[1]-y[1]) + abs(x[2]-y[2]))
    tot.append(sum(L.values())); rlay.update(L); glay.update(gl[n])
print('driver type', dict(drvt)); print('sink types', sink.most_common(8)); print('sink pin layers', sinklay.most_common(4))
print('violated layer entries', sorted(vlay.items())); print('fanout p10/50/90', q(fan))
print('routed length um p10/50/90', q(tot), 'sum', '%.0f' % sum(tot))
print('driver->viol sink manhattan um p10/50/90', q(dist))
s = sum(rlay.values()); print('DR length share by layer', ' '.join('%s %.1f%%' % (l, 100*rlay[l]/s) for l in LAY if rlay[l]))
s = sum(glay.values()); print('guide length share by layer', ' '.join('%s %.1f%%' % (l, 100*glay[l]/s) for l in LAY if glay[l]))
# population: nets touching a macro (driven by / sinking into), violation rate by length bin and by direction
pop = collections.Counter(); pv = collections.Counter(); prl = collections.Counter()
for n, (ps, L) in nets.items():
    if L is None: continue
    dv = drv(ps); kind = 'macro-driven' if dv and dv[2] in macros else 'macro-sink'
    b = min(4, int(sum(L.values()) // 500)); pop[(kind, b)] += 1; pv[(kind, b)] += n in viol
    if n not in viol: prl.update(L)
print('population (kind, length bin 500um) nets / violating:')
for k in sorted(pop): print('  ', k[0], '%d-%s' % (k[1]*500, (k[1]+1)*500 if k[1] < 4 else 'inf'), pop[k], pv[k])
s = sum(prl.values()); print('clean macro-net DR length share', ' '.join('%s %.1f%%' % (l, 100*prl[l]/s) for l in LAY if prl[l]))
