#!/usr/bin/env python3
# R33: routed length vs HPWL (instance origins / port positions) per signal net from a routed DEF.
# Reports, for 2-pin nets by HPWL bin, sum(routed)/sum(HPWL) and the p50/p90 of the per-net ratio; also per-direction
# routed length (H layers vs V layers) relative to dx / dy for 2-pin nets.
import sys, re
from collections import defaultdict
deff = sys.argv[1]; unit = 2000
comp = {}; pins = {}
H = set(sys.argv[2].split(',')); V = set(sys.argv[3].split(','))
sec = None; buf = []
bins = [(0,50),(50,200),(200,500),(500,1000),(1000,1e9)]
agg = defaultdict(lambda: [0.0, 0.0, []]); dirs = defaultdict(lambda: [0.0,0.0,0.0,0.0])
worst = []
def handle(stmt):
    tok = stmt.replace('(', ' ( ').replace(')', ' ) ').split()
    if not tok or tok[0] != '-': return
    if 'USE' in tok and tok[tok.index('USE') + 1] in ('POWER', 'GROUND', 'CLOCK'): return
    name = tok[1]
    # connections
    i = 2; conn = []
    while i < len(tok) and tok[i] == '(':
        j = tok.index(')', i); conn.append(tok[i+1:j]); i = j + 1
    pts = []
    for c in conn:
        if c[0] == 'PIN':
            if c[1] in pins: pts.append(pins[c[1]])
        elif c[0] in comp: pts.append(comp[c[0]])
    if len(pts) < 2: return
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    hp = (max(xs) - min(xs) + max(ys) - min(ys)) / unit
    per = defaultdict(float); layer = None; last = None; n = len(tok)
    while i < n:
        t = tok[i]
        if t in ('ROUTED', 'FIXED', 'COVER', 'NOSHIELD') and tok[i-1] == '+':
            layer = tok[i+1]; last = None; i += 2; continue
        if t == 'NEW': layer = tok[i+1]; last = None; i += 2; continue
        if t == '(' and layer is not None:
            j = tok.index(')', i); v = tok[i+1:j]
            if len(v) >= 2 and v[0] != 'PIN':
                x = last[0] if v[0] == '*' else int(v[0]); y = last[1] if v[1] == '*' else int(v[1])
                if last is not None: per[layer] += (abs(x-last[0]) + abs(y-last[1])) / unit
                last = (x, y)
            i = j + 1; continue
        if t == 'RECT':
            j = tok.index(')', i); i = j + 1; continue
        i += 1
    rl = sum(per.values())
    if rl == 0: return
    if len(pts) == 2:
        for k, (a, b) in enumerate(bins):
            if a <= hp < b:
                g = agg[k]; g[0] += rl; g[1] += hp; g[2].append(rl / max(hp, 1.0))
                if hp >= 200:
                    d = dirs[k]; d[0] += sum(v for l, v in per.items() if l in H); d[1] += (max(xs)-min(xs))/unit
                    d[2] += sum(v for l, v in per.items() if l in V); d[3] += (max(ys)-min(ys))/unit
                break
        if hp >= 300: worst.append((rl / hp, name, hp, rl))
with open(deff) as f:
    for line in f:
        if sec is None:
            if line.startswith('NETS '): sec = 'n'
            elif line.startswith('COMPONENTS '): sec = 'c'
            elif line.startswith('PINS '): sec = 'p'
            continue
        if line.startswith('END '):
            if sec == 'p' and buf: pass
            sec = None; buf = []; continue
        if sec == 'c':
            t = line.split()
            if len(t) > 2 and t[0] == '-' and '(' in t:
                k = t.index('('); comp[t[1]] = (int(t[k+1]), int(t[k+2]))
            continue
        if sec == 'p':
            buf.append(line)
            if line.rstrip().endswith(';'):
                s = ' '.join(buf); buf = []
                m = re.search(r'^\s*-\s+(\S+)', s); mm = re.search(r'PLACED\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)|FIXED\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)', s)
                if m and mm:
                    g = [x for x in mm.groups() if x is not None]; pins[m.group(1)] = (int(g[0]), int(g[1]))
            continue
        buf.append(line)
        if line.rstrip().endswith(';'):
            handle(' '.join(buf)); buf = []
for k, (a, b) in enumerate(bins):
    g = agg[k]
    if not g[2]: continue
    r = sorted(g[2]); n = len(r)
    print('DT33 2pin HPWL %4d-%-5s n %6d routed/HPWL sum %.3f p50 %.3f p90 %.3f p99 %.3f' % (a, int(b) if b < 1e9 else 'inf', n, g[0]/g[1], r[n//2], r[n*9//10], r[n*99//100]))
for k, d in sorted(dirs.items()):
    print('DT33 dir bin %d (HPWL>=200): H-layer len / dx %.3f, V-layer len / dy %.3f (dx %.0f mm dy %.0f mm)' % (k, d[0]/max(d[1],1), d[2]/max(d[3],1), d[1]/1000, d[3]/1000))
worst.sort(reverse=True)
for w in worst[:8]: print('DT33 worst ratio %.2f %s hpwl %.0f routed %.0f' % w)
