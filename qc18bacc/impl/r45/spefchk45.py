#!/usr/bin/env python3
"""R45 probe: topology check of SPEF D_NETs (connectivity, loops, floating cap nodes, pin-to-pin R) for nets whose name
matches a regex.  usage: spefchk45.py <spef> <net_regex> [flag-names...]"""
import sys, re, collections
spef, rx = sys.argv[1], re.compile(sys.argv[2]); flag = set(sys.argv[3:])
def parse(lines):
    name = lines[0].split()[1]; sec = None; conn = []; caps = {}; res = []
    for l in lines[1:]:
        t = l.split()
        if not t: continue
        if t[0] in ('*CONN', '*CAP', '*RES'): sec = t[0]; continue
        if sec == '*CONN' and t[0] in ('*I', '*P'): conn.append(t[1])
        elif sec == '*CAP' and len(t) == 3: caps[t[1]] = float(t[2])
        elif sec == '*RES' and len(t) == 4: res.append((t[1], t[2], float(t[3])))
    return name, conn, caps, res
out = []
with open(spef) as f:
    cur = None
    for line in f:
        if line.startswith('*D_NET'):
            cur = [line] if rx.match(line.split()[1]) else None
        elif cur is not None:
            if line.startswith('*END'):
                name, conn, caps, res = parse(cur); cur = None
                nodes = set(caps) | set(conn) | {a for a, b, r in res} | {b for a, b, r in res}
                par = {n: n for n in nodes}
                def find(x):
                    while par[x] != x: par[x] = par[par[x]]; x = par[x]
                    return x
                loops = 0
                for a, b, r in res:
                    ra, rb = find(a), find(b)
                    if ra == rb: loops += 1
                    else: par[ra] = rb
                comps = len({find(n) for n in nodes})
                pin_comps = len({find(n) for n in conn})
                g = collections.defaultdict(list)
                for a, b, r in res: g[a].append((b, r)); g[b].append((a, r))
                # driver = *P (input port) else first conn
                src = next((c for c in conn if ':' not in c), conn[0] if conn else None)
                dist = {src: 0.0}; st = [src]
                while st:
                    x = st.pop()
                    for y, r in g[x]:
                        if y not in dist: dist[y] = dist[x] + r; st.append(y)
                rmax = max((dist.get(c, -1) for c in conn), default=0)
                out.append((name, round(sum(caps.values()), 2), len(nodes), len(res), loops, comps, pin_comps, round(rmax, 1), name in flag))
            else:
                cur.append(line)
print('name cap_fF nodes res loops comps pin_comps maxR_ohm flagged')
for o in out:
    if o[4] or o[6] > 1 or o[8]: print(*o)
n = len(out); print('nets', n, 'with loops', sum(1 for o in out if o[4]), 'pins in >1 component', sum(1 for o in out if o[6] > 1))
print('top by maxR:')
for o in sorted(out, key=lambda o: -o[7])[:15]: print(' ', *o)
print('top by cap:')
for o in sorted(out, key=lambda o: -o[1])[:5]: print(' ', *o)
