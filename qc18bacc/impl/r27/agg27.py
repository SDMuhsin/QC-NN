"""R27 (results/r27.md): aggregate attr27.tcl <out>.trees by logical bus.  Group of a root net: its net stem unless
anonymous (nN / netN / UN), else the driver stem unless anonymous, else '~' + the most common named sink stem
(M:<macro>.<pin>, P:<port>), else 'anon'.  Prints the top-N groups by added area (inserted buffer + resize delta)."""
import re, sys, statistics as st
ANON = re.compile(r'^(nN|netN|UN|N|U|-)$')
f, top = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 12
G = {}; tot = 0.0; long_a = 0.0; nb_t = 0
for l in open(f):
    t = l.split()
    if len(t) < 15 or t[0] != 'T': continue
    nb, ab, ar, hp, md, sp = int(t[4]), float(t[5]), float(t[6]), float(t[7]), float(t[8]), int(t[9])
    ns, ds, sk = t[11], t[12], t[13]
    g = ns if not ANON.match(ns) else ds if not ANON.match(ds) else ('~' + sk if sk != '-' else 'anon')
    a = ab + ar; tot += a; nb_t += nb
    if hp > 1000: long_a += a
    r = G.setdefault(g, [0, 0, 0.0, 0.0, 0.0, 0, []])
    r[0] += 1; r[1] += nb; r[2] += ab; r[3] += ar; r[4] += hp; r[5] += sp; r[6].append(md)
print(f'R27_AGG total added {tot:.0f} um2 (buffers {nb_t}), on nets with HPWL > 1 mm {long_a:.0f} um2 = {100*long_a/tot:.1f} %, groups {len(G)}')
print('group nets nbuf buf_um2 rsz_um2 added_um2 %tot hpwl_mm span% md_med md_max')
for g, r in sorted(G.items(), key=lambda kv: -(kv[1][2] + kv[1][3]))[:top]:
    a = r[2] + r[3]
    print(f'{g} {r[0]} {r[1]} {r[2]:.0f} {r[3]:.0f} {a:.0f} {100*a/tot:.1f} {r[4]/1000:.1f} {100*r[5]/r[0]:.0f} {st.median(r[6]):.0f} {max(r[6]):.0f}')
# coarse classes: '~' sink-labelled vs named, and by HPWL band
B = {}
for l in open(f):
    t = l.split()
    if len(t) < 15 or t[0] != 'T': continue
    hp = float(t[7]); k = '<0.2' if hp < 200 else '0.2-0.5' if hp < 500 else '0.5-1' if hp < 1000 else '1-2' if hp < 2000 else '>2'
    r = B.setdefault(k, [0, 0, 0.0]); r[0] += 1; r[1] += int(t[4]); r[2] += float(t[5]) + float(t[6])
print('R27_BAND ' + ' | '.join(f'{k} mm: nets {r[0]} buf {r[1]} added {r[2]:.0f} ({100*r[2]/tot:.1f} %)' for k, r in sorted(B.items())))
