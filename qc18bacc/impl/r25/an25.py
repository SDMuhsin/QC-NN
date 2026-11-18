#!/usr/bin/env python3
"""R25: DR marker map of a hub run.  an25.py <dump dir (dump25.tcl)> <drt.drc.rpt>
Bins markers (bbox centre) into 50 um bins, prints the top bins with std-cell density / pins / macro context, the marker
share of the top 1 / 5 / 10 % bins, Spearman(markers, density | pins) and the markers within 10 um of a macro edge, a
macro signal pin or a block pin.  Prints aggregates only."""
import sys, re, math, collections as C
dd, rpt = sys.argv[1], sys.argv[2]
B, NEAR, WEST = 50.0, 10.0, 860.0
mac = []
for l in open(f"{dd}/mac.txt"):
    t = l.split()
    if t[0] == "DIE": die = list(map(float, t[1:]))
    else: mac.append((t[0], t[1], *map(float, t[2:6])))
NX, NY = int((die[2] - die[0]) / B), int((die[3] - die[1]) / B)  # edge slivers merge into the last bin
area, ncell, npin = C.Counter(), C.Counter(), C.Counter()
for l in open(f"{dd}/bins.txt"):
    t = l.split(); k = (min(NX - 1, int(t[0])), min(NY - 1, int(t[1]))); area[k] += float(t[2]); ncell[k] += int(t[3]); npin[k] += int(t[4])
def pts(fn):
    r = []
    for l in open(fn):
        t = l.split(); r.append((float(t[-2]), float(t[-1]), t[0]))
    return r
mpin, bterm = pts(f"{dd}/mpin.txt"), pts(f"{dd}/bterm.txt")
def binof(x, y): return (min(NX - 1, int((x - die[0]) / B)), min(NY - 1, int((y - die[1]) / B)))
mpb, btb = C.Counter(binof(x, y) for x, y, _ in mpin), C.Counter(binof(x, y) for x, y, _ in bterm)
def ov(a0, a1, b0, b1): return max(0.0, min(a1, b1) - max(a0, b0))
free, macin = {}, {}
for ix in range(NX):
    for iy in range(NY):
        x0, y0 = die[0] + ix * B, die[1] + iy * B; x1 = die[2] if ix == NX - 1 else x0 + B; y1 = die[3] if iy == NY - 1 else y0 + B
        mo = 0.0; names = C.Counter()
        for n, m, a, b, c, d in mac:
            o = ov(x0, x1, a, c) * ov(y0, y1, b, d)
            if o > 0: mo += o; names[m] += o
        free[(ix, iy)] = (x1 - x0) * (y1 - y0) - mo; macin[(ix, iy)] = names
def dens(k): return area[k] / free[k] if free[k] > 0.1 * B * B else float("nan")
# markers
mk = []; cur = None; src = None
rb = re.compile(r"bbox = \( ([-\d.]+), ([-\d.]+) \) - \( ([-\d.]+), ([-\d.]+) \) on Layer (\S+)")
for l in open(rpt):
    if "violation type:" in l: cur = l.split(":", 1)[1].strip()
    elif "srcs:" in l:
        s = l.split()[1:]; src = "-".join(sorted(set(x.split(":")[0] for x in s))) or "none"
    else:
        m = rb.search(l)
        if m:
            a, b, c, d = map(float, m.group(1, 2, 3, 4)); mk.append(((a + c) / 2, (b + d) / 2, m.group(5), cur, src))
N = len(mk); print(f"R25_MK markers {N} bins {NX}x{NY}={NX*NY}")
print("R25_MK by layer/type:", "; ".join(f"{k[0]} {k[1]} {v}" for k, v in C.Counter((m[2], m[3]) for m in mk).most_common(8)))
print("R25_MK srcs:", "; ".join(f"{k} {v}" for k, v in C.Counter(m[4] for m in mk).most_common(5)))
cnt = C.Counter(binof(m[0], m[1]) for m in mk)
allb = [(ix, iy) for ix in range(NX) for iy in range(NY)]
srt = sorted(allb, key=lambda k: -cnt[k])
for p in (1, 5, 10, 25):
    n = max(1, round(len(allb) * p / 100)); print(f"R25_TOP {p}% bins ({n}): {sum(cnt[k] for k in srt[:n]) / N * 100:.1f} % of markers")
def edist(x, y, a, b, c, d):  # distance to the rectangle boundary
    if a <= x <= c and b <= y <= d: return min(x - a, c - x, y - b, d - y)
    dx = max(a - x, 0, x - c); dy = max(b - y, 0, y - d); return math.hypot(dx, dy)
def near_mac(x, y):
    best = (1e9, None)
    for n, m, a, b, c, d in mac:
        e = edist(x, y, a, b, c, d)
        if e < best[0]: best = (e, m)
    return best
def grid(ps):
    g = C.defaultdict(list)
    for x, y, n in ps: g[(int(x // NEAR), int(y // NEAR))].append((x, y))
    return g
gm, gb = grid(mpin), grid(bterm)
def near(g, x, y):
    i, j = int(x // NEAR), int(y // NEAR)
    return any(math.hypot(x - u, y - v) <= NEAR for di in (-1, 0, 1) for dj in (-1, 0, 1) for u, v in g.get((i + di, j + dj), ()))
nme = nmp = nbt = nany = nin = 0
for x, y, *_ in mk:
    e, _m = near_mac(x, y); inside = any(a <= x <= c and b <= y <= d for _n, _mm, a, b, c, d in mac)
    a1, a2, a3 = e <= NEAR, near(gm, x, y), near(gb, x, y)
    nme += a1; nmp += a2; nbt += a3; nany += a1 or a2 or a3; nin += inside
print(f"R25_NEAR within {NEAR:.0f} um: macro edge {nme} ({nme/N*100:.1f} %), macro signal pin {nmp} ({nmp/N*100:.1f} %), "
      f"block pin {nbt} ({nbt/N*100:.1f} %), any {nany} ({nany/N*100:.1f} %); inside a macro {nin} ({nin/N*100:.1f} %); "
      f"west of x {WEST:.0f}: {sum(m[0] < WEST for m in mk)/N*100:.1f} %")
# baseline: share of the non-macro die area (5 um sample grid) inside the same near zones
tot = zme = zmp = zbt = 0
for i in range(int((die[2] - die[0]) / 5)):
    for j in range(int((die[3] - die[1]) / 5)):
        x, y = die[0] + 5 * i + 2.5, die[1] + 5 * j + 2.5
        if any(a <= x <= c and b <= y <= d for _n, _m, a, b, c, d in mac): continue
        tot += 1; zme += near_mac(x, y)[0] <= NEAR; zmp += near(gm, x, y); zbt += near(gb, x, y)
print(f"R25_BASE non-macro area share within {NEAR:.0f} um: macro edge {zme/tot*100:.1f} %, macro pin {zmp/tot*100:.1f} %, "
      f"block pin {zbt/tot*100:.1f} %;")
def rank(v):
    o = sorted(range(len(v)), key=lambda i: v[i]); r = [0.0] * len(v); i = 0
    while i < len(o):
        j = i
        while j + 1 < len(o) and v[o[j + 1]] == v[o[i]]: j += 1
        for q in range(i, j + 1): r[o[q]] = (i + j) / 2
        i = j + 1
    return r
def sp(a, b):
    ra, rb_ = rank(a), rank(b); n = len(a); ma, mb = sum(ra) / n, sum(rb_) / n
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb_))
    return num / math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb_))
std = [k for k in allb if free[k] >= 0.5 * B * B]
for lab, ks in (("all bins", allb), ("bins >=50% free of macros", std)):
    ks2 = [k for k in ks if not math.isnan(dens(k))] if lab != "all bins" else ks
    c = [cnt[k] for k in ks2]
    dv = [area[k] / max(free[k], 1.0) for k in ks2]; pv = [npin[k] for k in ks2]; pd = [npin[k] / max(free[k], 1.0) for k in ks2]
    mp = [mpb[k] + btb[k] for k in ks2]
    print(f"R25_SP {lab} n={len(ks2)}: rho(markers, std density) {sp(c, dv):+.3f}; rho(markers, std pins) {sp(c, pv):+.3f}; "
          f"rho(markers, pins/free um2) {sp(c, pd):+.3f}; rho(markers, macro+block pins) {sp(c, mp):+.3f}")
# density distribution of marker-weighted bins vs all std bins
def q(v, f): v = sorted(v); return v[min(len(v) - 1, int(f * len(v)))]
ds = [dens(k) for k in std if area[k] > 0]
print(f"R25_DENS std bins (>=50% free): density p50 {q(ds,.5):.2f} p90 {q(ds,.9):.2f} max {max(ds):.2f}; "
      f"marker-weighted mean density {sum(cnt[k]*dens(k) for k in std)/max(1,sum(cnt[k] for k in std)):.2f} "
      f"(bins >=50% free hold {sum(cnt[k] for k in std)/N*100:.1f} % of markers)")
for i, k in enumerate(srt[:10]):
    x0, y0 = die[0] + k[0] * B, die[1] + k[1] * B
    ms = [m for m in mk if binof(m[0], m[1]) == k]
    lt = C.Counter((m[2], m[3].split()[0]) for m in ms).most_common(3)
    e, mm = near_mac(x0 + 25, y0 + 25); mn = ",".join(f"{n}:{v/(B*B)*100:.0f}%" for n, v in macin[k].most_common(2))
    d = dens(k)
    print(f"R25_BIN {i+1} x {x0:.0f}-{x0+B:.0f} y {y0:.0f}-{y0+B:.0f} [{k[0]},{k[1]}]: {cnt[k]} markers ({'; '.join(f'{a} {b} {v}' for (a, b), v in lt)}) | "
          f"std density {d:.2f} cells {ncell[k]} std pins {npin[k]} macro pins {mpb[k]} block pins {btb[k]} | macro cover {mn or '-'} "
          f"centre-to-macro-edge {e:.0f} um ({mm}) {'WEST<860' if x0 < WEST else ''}")
# density classes: threshold (local hotspot) vs proportional behaviour
tp = sum(npin[k] for k in std)
for lo, hi in ((0, .6), (.6, .7), (.7, .8), (.8, .9), (.9, 2)):
    ks = [k for k in std if lo <= dens(k) < hi]
    m = sum(cnt[k] for k in ks); p = sum(npin[k] for k in ks)
    print(f"R25_DCLS density [{lo:.1f},{hi:.1f}): bins {len(ks)} pins {p/tp*100:.1f} % markers {m/N*100:.1f} % markers/kpin {m/max(p,1)*1000:.1f}")
top10 = set(srt[:max(1, round(len(allb) * .10))])
for (ly, ty), v in C.Counter((m[2], m[3]) for m in mk).most_common(6):
    sub = [m for m in mk if m[2] == ly and m[3] == ty]; cb = C.Counter(binof(m[0], m[1]) for m in sub)
    t10 = sum(cb[k] for k in top10) / v * 100
    nr = sum(1 for m in sub if near_mac(m[0], m[1])[0] <= NEAR or near(gm, m[0], m[1]) or near(gb, m[0], m[1])) / v * 100
    print(f"R25_LAYER {ly} {ty} {v}: in top-10% bins {t10:.1f} %, rho(vs pins/free, std bins) {sp([cb[k] for k in std], [npin[k]/max(free[k],1) for k in std]):+.3f}, "
          f"near macro edge/pin/block pin {nr:.1f} %, west of {WEST:.0f} {sum(m[0] < WEST for m in sub)/v*100:.1f} %")
wa = sum(free[k] for k in allb if die[0] + k[0] * B < WEST) / sum(free[k] for k in allb) * 100
print(f"R25_BASE2 non-macro area west of x {WEST:.0f}: {wa:.1f} %; std pins west {sum(npin[k] for k in allb if die[0]+k[0]*B < WEST)/sum(npin.values())*100:.1f} %")
mm = C.defaultdict(list)
for n, m, a, b, c, d in mac: mm[m].append((a, b, c, d))
print("R25_MAC " + "; ".join(f"{m} x{len(r)} x {min(q[0] for q in r):.0f}-{max(q[2] for q in r):.0f} y {min(q[1] for q in r):.0f}-{max(q[3] for q in r):.0f}" for m, r in mm.items()))
yb = C.Counter(k[1] for k in allb for _ in range(cnt[k]))
print("R25_YPROF markers per 50 um row (y lo: %): " + " ".join(f"{iy*50}:{yb[iy]/N*100:.0f}" for iy in range(NY) if yb[iy] / N >= 0.01))
xb = C.Counter(k[0] for k in allb for _ in range(cnt[k]))
print("R25_XPROF markers per 200 um column (x lo: %): " + " ".join(f"{ix*200}:{sum(xb[j] for j in range(4*ix, 4*ix+4))/N*100:.0f}" for ix in range(NX // 4 + 1)))
