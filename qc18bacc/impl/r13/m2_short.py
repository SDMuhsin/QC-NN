#!/usr/bin/env python3
"""R13 (results/r13.md): where are the DR M2 shorts of qb_act2_blk?  Bins the M2 short markers of a drt.drc.rpt and the
cells of a cell_dump.tcl dump on a B-um grid (default 10) and reports, per marker-density decile of the bins: cell
utilisation, signal pins per um2 / per M2 track length, share of cell classes (repair buffers, pre-mux MUX, S1 AND-OR,
line-buffer flops, ICG, other) and the top masters in the hottest bins.  <drt.drc.rpt> = '-' (placement only, no route):
deciles by signal-pin density instead.
   m2_short.py <drt.drc.rpt> <cells.txt> [B_um] [layer]"""
import re, sys, collections as C
rpt, cells = sys.argv[1], sys.argv[2]
B = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
LAY = sys.argv[4] if len(sys.argv) > 4 else 'M2'
mk = C.Counter(); typ = None
for line in (open(rpt) if rpt != '-' else []):
    if 'violation type' in line: typ = line.split(':', 1)[1].strip()
    elif 'bbox' in line and typ == 'Short':
        m = re.search(r'\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*-\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*on Layer (\S+)', line)
        if m and m.group(5) == LAY: mk[(int(float(m.group(1)) // B), int(float(m.group(2)) // B))] += 1
def cls(master, name):
    if re.search(r'(rebuffer|split|wire|max_cap|max_length|repair|place\d)', name) and re.match(r'(BUFF|INV|CKBD|CKND)', master): return 'repair_buf'
    if re.match(r'(BUFF|INV|CKBD|CKND|DEL)', master): return 'dc_buf'
    if re.match(r'(FILL|DCAP|TAP|ANTENNA|GFILL)', master): return 'fill'
    if re.match(r'(CKLN|CKLH)', master): return 'icg'
    if re.match(r'(DF|EDF|SDF|LH|LN)', master): return 'lb_ff' if 'u_lb' in name else 'ff'
    if 'u_pm' in name or 'g_pmr' in name: return 'premux'
    if 'u_s1' in name: return 's1'
    if 'u_s2' in name: return 's2'
    if 'u_lb' in name: return 'lb_logic'
    return 'other'
area, pins, cnt, ccls, mst = C.Counter(), C.Counter(), C.Counter(), C.defaultdict(C.Counter), C.defaultdict(C.Counter)
tot_cls = C.Counter()
for line in open(cells):
    p = line.split()
    if len(p) < 7: continue
    m, x0, y0, x1, y1, n, nm = p[0], *map(float, p[1:5]), int(p[5]), p[6]
    c = cls(m, nm)
    if c == 'fill': continue
    k = (int(((x0 + x1) / 2) // B), int(((y0 + y1) / 2) // B))
    a = (x1 - x0) * (y1 - y0)
    area[k] += a; pins[k] += n; cnt[k] += 1; ccls[k][c] += a; mst[k][m] += 1; tot_cls[c] += a
keys = sorted(set(area) | set(mk), key=(lambda k: mk[k]) if rpt != '-' else (lambda k: pins[k]))
nb = len(keys); tot = sum(mk.values())
print(f'# {LAY} shorts {tot} in {sum(1 for k in keys if mk[k])} of {nb} {B:g}-um bins; cell area classes (um2): ' +
      ', '.join(f'{c} {a:.0f}' for c, a in tot_cls.most_common()))
print('# decile  shorts/bin  share  util  pins/um2  cells/bin  ' + '  '.join(f'{c:>10s}' for c in ['repair_buf', 'dc_buf', 'premux', 's1', 's2', 'lb_ff', 'lb_logic', 'icg', 'ff', 'other']))
for d in range(10):
    ks = keys[d * nb // 10:(d + 1) * nb // 10]
    if not ks: continue
    A = sum(area[k] for k in ks); P = sum(pins[k] for k in ks); S = sum(mk[k] for k in ks)
    sh = {c: sum(ccls[k][c] for k in ks) / max(A, 1) for c in ['repair_buf', 'dc_buf', 'premux', 's1', 's2', 'lb_ff', 'lb_logic', 'icg', 'ff', 'other']}
    print(f'{d:6d}  {S / len(ks):10.1f}  {S / max(tot, 1):5.3f}  {A / (len(ks) * B * B):4.2f}  {P / (len(ks) * B * B):8.3f}  {sum(cnt[k] for k in ks) / len(ks):9.1f}  ' +
          '  '.join(f'{sh[c]:10.3f}' for c in sh))
top = keys[-max(1, nb // 100):]
mm = C.Counter()
for k in top: mm.update(mst[k])
print('# top 1 % bins: masters', ', '.join(f'{m} {c}' for m, c in mm.most_common(15)))
