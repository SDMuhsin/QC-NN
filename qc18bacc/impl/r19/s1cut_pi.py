import sys, collections, statistics as st
sys.path.insert(0, 'hw/tb')
import gen_act2_s2m as M
regs, t1, t2 = M.build()
rd = collections.defaultdict(list)    # G -> list of home rows (one per S1 reg term)
for r in regs:
    for G in t1[r]: rd[G].append(r[0])
def cuts(place):
    c = [0]*15
    for G, rows in rd.items():
        p = place(G, rows); lo, hi = min(rows+[p]), max(rows+[p])
        for k in range(lo, hi): c[k] += 32
    return c
med = cuts(lambda G, rows: sorted(rows)[len(rows)//2])

print('lbm crossings per cut, lb word at median reader row:', med, 'max', max(med))
print('S1 term count', sum(len(v) for v in rd.values()), 'words', len(rd))
plc = {G: sorted(rows)[len(rows)//2] for G, rows in rd.items()}
# partial-OR per (reg, source row): one 32-b wire from source row to home row
c = [0]*15; nsrc = []
for r in regs:
    srcs = {plc[G] for G in t1[r]}; nsrc.append(len(srcs))
    for s in srcs:
        lo, hi = min(s, r[0]), max(s, r[0])
        for k in range(lo, hi): c[k] += 32
print('pre-OR at source rows: crossings', c, 'max', max(c), 'distinct src rows/reg mean %.2f' % st.mean(nsrc))
# also lbm local fanout is then within a row band only
# unread words: place at median of the read words of the same j (else row 7)
for s in range(8):
    for j in range(64):
        G = 64*s+j
        if G not in plc:
            o = sorted(plc[64*t+j] for t in range(8) if 64*t+j in plc)
            plc[G] = o[len(o)//2] if o else 7
def add(c, pts, w=32):
    for k in range(min(pts), max(pts)): c[k] += w
sh = [0]*15; wr = [0]*15
for s in range(8):
    for j in range(64):
        pts = [plc[64*s+j]] + [plc[64*(s-d)+j] for d in (1,2,4) if s-d >= 0]
        add(sh, pts)
for j in range(64):
    add(wr, [plc[64*s+j] for s in range(8)] + [0])   # write data enters at the south edge (row 0)
print('shift crossings', sh, 'max', max(sh))
print('write crossings (x2 contexts)', [2*v for v in wr], 'max', 2*max(wr))
tot = [a+b+2*d for a,b,d in zip(c, sh, wr)]
print('S1 partial-OR + shift + write (x2 ctx write; shift x2 ctx)', [a+2*b+2*d for a,b,d in zip(c, sh, wr)])
print('--- slot-co-located: one row per j')
best = None
def evalj(pj):
    c=[0]*15
    for r in regs:
        for s_ in {pj[G % 64] for G in t1[r]}:
            add(c, [s_, r[0]])
    w=[0]*15
    add(w, [0, max(pj.values())])   # write bus spans to the topmost j-row: 2048 b x 2 ctx -- approx as full bus
    return c
allr = collections.defaultdict(list)
for G, rows in rd.items(): allr[G % 64] += rows
pj = {j: (sorted(allr[j])[len(allr[j])//2] if allr[j] else 7) for j in range(64)}
c1 = evalj(pj)
print('partial-OR, j at median: S1 crossings', c1, 'max', max(c1))
# current-style reference: S1 trees all in middle band, lb spread uniformly (lbm nets from anywhere to the middle), ~ R18 measured 8.3 k at cut 7/8
# greedy improve
import random
random.seed(1)
cur = max(c1); 
for it in range(4000):
    j = random.randrange(64); old = pj[j]; pj[j] = random.randrange(16)
    m = max(evalj(pj))
    if m <= cur: cur = m
    else: pj[j] = old
c2 = evalj(pj); print('greedy minmax: ', c2, 'max', max(c2))
