#!/usr/bin/env python3
# R33: per-layer routed wirelength from a DEF (global, long nets, named nets) + locations of named instances
import sys, re
from collections import defaultdict
deff = sys.argv[1]; names = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else set()
insts = set(sys.argv[3].split(',')) if len(sys.argv) > 3 else set()
unit = 2000
glob = defaultdict(float); longl = defaultdict(float); nlong = 0
bins = defaultdict(lambda: defaultdict(float))  # length bin -> layer -> um
sec = None; buf = []
def handle(stmt):
    global nlong
    tok = stmt.replace('(', ' ( ').replace(')', ' ) ').split()
    if not tok or tok[0] != '-': return
    name = tok[1].replace('\\', '')
    if 'USE' in tok and tok[tok.index('USE') + 1] in ('POWER', 'GROUND'): return
    per = defaultdict(float); layer = None; last = None; i = 0; n = len(tok)
    while i < n:
        t = tok[i]
        if t in ('ROUTED', 'FIXED', 'COVER', 'NOSHIELD') and i > 0 and tok[i-1] == '+':
            layer = tok[i+1]; last = None; i += 2; continue
        if t == 'NEW': layer = tok[i+1]; last = None; i += 2; continue
        if t == '(' and layer is not None:
            j = tok.index(')', i); v = tok[i+1:j]
            if len(v) >= 2:
                x = last[0] if v[0] == '*' else int(v[0]); y = last[1] if v[1] == '*' else int(v[1])
                if last is not None: per[layer] += (abs(x-last[0]) + abs(y-last[1])) / unit
                last = (x, y)
            i = j + 1; continue
        if t == 'RECT':
            j = tok.index(')', i); i = j + 1; continue
        i += 1
    tot = sum(per.values())
    for l, v in per.items(): glob[l] += v
    b = 0 if tot < 100 else 1 if tot < 500 else 2 if tot < 1000 else 3
    for l, v in per.items(): bins[b][l] += v
    if name in names:
        print('NET %s total %.0f %s' % (name, tot, ' '.join('%s:%.0f' % kv for kv in sorted(per.items()))))
with open(deff) as f:
    for line in f:
        if sec is None:
            if line.startswith('NETS '): sec = 'n'
            elif line.startswith('COMPONENTS '): sec = 'c'
            continue
        if line.startswith('END NETS') or line.startswith('END COMPONENTS'):
            sec = None; continue
        if sec == 'c':
            if insts:
                t = line.split()
                if len(t) > 2 and t[0] == '-' and t[1].replace('\\', '') in insts:
                    k = t.index('(') if '(' in t else None
                    if k: print('INST %s %s at %.1f %.1f %s' % (t[1].replace('\\',''), t[2], int(t[k+1])/unit, int(t[k+2])/unit, t[k+4] if len(t)>k+4 else ''))
            continue
        buf.append(line)
        if line.rstrip().endswith(';'):
            handle(' '.join(buf)); buf = []
L = sorted(glob)
print('GLOBAL ' + ' '.join('%s:%.0fmm' % (l, glob[l]/1000) for l in L))
for b, lab in enumerate(['<100um', '100-500', '500-1000', '>1000um']):
    tt = sum(bins[b].values()) or 1
    print('BIN %s total %.0fmm %s' % (lab, tt/1000, ' '.join('%s:%.1f%%' % (l, 100*bins[b][l]/tt) for l in L)))
