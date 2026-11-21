# R38 KLayout probe: for the first N results of a rule in a Calibre ASCII DRC results db, list which cells own the shapes
# of the given GDS layers touching the result (TOP = block-level routing / DEF geometry, else the std-cell name).
#   python3 klrun.py -b -r probe38.py -rd gds=<x.gds> -rd rdb=<DRC_RES.db> -rd rule=<name> -rd layers="31/0 51/0" [-rd n=20]
import collections
ly = pya.Layout(); ly.read(gds); top = ly.top_cell(); s = 0.001 / ly.dbu
lis = [(L, ly.find_layer(int(L.split('/')[0]), int(L.split('/')[1]))) for L in layers.split()]
N = int(globals().get('n', 20)); res = []; cur = None; pts = []
for line in open(rdb):
    t = line.split()
    if len(t) == 1 and t[0] != '}' and not t[0][0].isdigit(): cur = t[0]; continue
    if cur == rule and t and t[0] in ('e', 'p'):
        if pts: res.append(pts)
        pts = []; continue
    if cur == rule and len(t) in (2, 4) and t[0].lstrip('-').isdigit():
        pts.append([int(v) for v in t])
    if len(res) >= N: break
if pts and len(res) < N: res.append(pts)
tot = collections.Counter()
for k, r in enumerate(res):
    xs = [v for p in r for v in p[0::2]]; ys = [v for p in r for v in p[1::2]]
    box = pya.Box(int(min(xs) * s) - 2, int(min(ys) * s) - 2, int(max(xs) * s) + 2, int(max(ys) * s) + 2)
    own = []
    for L, li in lis:
        if li is None: continue
        it = top.begin_shapes_rec_touching(li, box)
        while not it.at_end():
            c = it.cell().name if it.cell().cell_index() != top.cell_index() else 'TOP'
            own.append('%s:%s' % (L, c)); it.next()
    c = collections.Counter(own); tot.update(set(c))
    print('PROBE %s #%d at %.3f %.3f: %s' % (rule, k, min(xs) / 1000.0, min(ys) / 1000.0, ' '.join('%s x%d' % kv for kv in sorted(c.items()))))
print('PROBE_SUM', rule, ' '.join('%s=%d' % kv for kv in tot.most_common(15)))
