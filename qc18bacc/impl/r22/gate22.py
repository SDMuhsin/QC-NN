#!/usr/bin/env python3
"""R22 budget gate (results/r22.md) from impl/r21/budget.sh outputs of a placed hub run (no new measurement model):
    python3 -I gate22.py <bud_dir> <run_dir> [limit 0.75] [util 0.80]
<bud_dir>/cuts21_rows_adj0.25.txt (impl/r21/cuts21.py, every cut segment), <bud_dir>/q1.log (impl/r12/q1.py),
<run_dir>/mplace.tcl (::QB15_BANDS), <run_dir>/summary.txt (place line).  Prints the R21 items 1-4 on the new
floorplan, the worst layer-summed cut per (kind, region), per-layer over-budget counts and PASS / FAIL:
PASS = every layer-summed cut (allH / allV) <= limit and placed util <= util limit."""
import re
import sys
import collections as C

bd, rd = sys.argv[1], sys.argv[2]
LIM = float(sys.argv[3]) if len(sys.argv) > 3 else 0.75
ULIM = float(sys.argv[4]) if len(sys.argv) > 4 else 0.80
R = []
for ln in open(bd + '/cuts21_rows_adj0.25.txt'):
    m = re.match(r'(\S) +([\d.]+) (\S+) +(\S+) +(\d+) / +([\d.]+) = +([\d.]+) % \| ?(.*)', ln)
    if m: R.append((m.group(1), float(m.group(2)), m.group(3), m.group(4), int(m.group(5)), float(m.group(6)), float(m.group(7)), m.group(8)))
b = re.search(r'set ::QB15_BANDS \{(.*)\}', open(rd + '/mplace.tcl').read()).group(1).split()
bands = {b[i]: (float(b[i + 1]), float(b[i + 2])) for i in range(0, len(b), 3)}
def short(r): return '%s %6.1f %-6s %-4s %6d/%6.0f = %5.1f %% | %s' % (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7][:110])
def worst(f):
    rr = [r for r in R if f(r)]
    return max(rr, key=lambda r: r[6]) if rr else None
lb0 = bands.get('band_mid') or bands['band_top']
nS = [v for k, v in bands.items() if k in ('S0', 'S1', 'S2', 'S3') and v[0] >= lb0[1] - 1]   # S rows north of the band
s2a, s3b = (min(v[0] for v in nS), max(v[1] for v in nS)) if nS else (bands['S2'][0], bands['S3'][1])
lb = bands.get('band_mid') or bands['band_top']                     # main logic band
breg = 'band' if any(r[2] == 'band' for r in R) else 'north'     # its cuts21 region (base: above S3 = north)
items = [
    ('1 V over north S rows (cols 1-7)', lambda r: r[0] == 'y' and r[3] == 'allV' and r[2] in ['col%d' % c for c in range(1, 8)] and s2a <= r[1] <= s3b),
    ('1b same, col0', lambda r: r[0] == 'y' and r[3] == 'allV' and r[2] == 'col0' and s2a <= r[1] <= s3b),
    ('2 H band (all x)', lambda r: r[0] == 'x' and r[3] == 'allH' and r[2] == breg),
    ('3 x 860 (any region) allH', lambda r: r[0] == 'x' and abs(r[1] - 860) < 1 and r[3] == 'allH'),
    ('3b x 860 (any region) M5/M7/M9', lambda r: r[0] == 'x' and abs(r[1] - 860) < 1 and r[3] in ('M5', 'M7', 'M9')),
    ('4 V north of S3 (col0-7)', lambda r: r[0] == 'y' and r[3] == 'allV' and r[2].startswith('col') and r[1] > s3b),
    ('5 V band (col0-7)', lambda r: r[0] == 'y' and r[3] == 'allV' and r[2].startswith('col') and lb[0] <= r[1] < lb[1]),
]
print('# R22 gate22: %s  (limit %.0f %% layer-summed at adj 0.25, util <= %.2f)' % (rd, 100 * LIM, ULIM))
print('# bands ' + '  '.join('%s %.0f-%.0f' % (k, v[0], v[1]) for k, v in bands.items()))
for nm, f in items:
    w = worst(f)
    print('ITEM %-30s %s' % (nm, short(w) if w else '-'))
print('# worst layer-summed cut per (kind, region)')
seen = C.OrderedDict()
for r in sorted(R, key=lambda r: -r[6]):
    if r[3] in ('allH', 'allV') and (r[0], r[2]) not in seen: seen[(r[0], r[2])] = r
for k in sorted(seen, key=lambda k: -seen[k][6]): print('WORST ' + short(seen[k]))
ovl = C.Counter(r[3] for r in R if r[3] not in ('allH', 'allV') and r[6] > 100 * LIM and r[5] > 50)
print('# per-layer segments > %.0f %% (cap > 50): %s' % (100 * LIM, ' '.join('%s %d' % kv for kv in sorted(ovl.items()))))
q = open(bd + '/q1.log').read()
m = re.search(r'init std area (\d+) um2 .*placed (\d+) um2', q)
wa = re.search(r'added wire +\d+ inst +([+\-]\d+)', q); fa = re.search(r'added fanout +\d+ inst +([+\-]\d+)', q)
rs = re.search(r'resized .*?([+\-]\d+) um2', q)
u = None
for ln in open(rd + '/summary.txt'):
    if ln.startswith('place die_um'):
        u = float(re.search(r'utilisation ([\d.]+)', ln).group(1)); ca = float(re.search(r'cell_um2 ([\d.]+)', ln).group(1))
        co, ma = float(re.search(r'core_um2 ([\d.]+)', ln).group(1)), float(re.search(r'macro_um2 ([\d.]+)', ln).group(1))
if m: print('Q1 std init %.3f -> placed %.3f mm2 (+%.3f): wire buffers %s, fanout buffers %s, resize %s um2' % (
    int(m.group(1)) / 1e6, int(m.group(2)) / 1e6, (int(m.group(2)) - int(m.group(1))) / 1e6,
    wa.group(1) if wa else '?', fa.group(1) if fa else '?', rs.group(1) if rs else '?'))
print('UTIL place %s (std + macro) / core; std %.3f mm2 / (core - macro) %.3f mm2 = %.3f' % (u, ca / 1e6, (co - ma) / 1e6, ca / (co - ma)))
wc = max((r for r in R if r[3] in ('allH', 'allV')), key=lambda r: r[6])
ok = wc[6] <= 100 * LIM and u is not None and u <= ULIM
print('GATE %s: worst layer-summed cut %.1f %% (%s %.0f %s), util %s' % ('PASS' if ok else 'FAIL', wc[6], wc[0], wc[1], wc[2], u))
