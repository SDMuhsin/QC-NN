#!/usr/bin/env python3
"""Routed DEF -> SPEF (distributed RC, grounded caps) with the captable-derived per-layer RC.

    def2spef.py <routed.def> <design.conn> <rc_corner.txt> <out.spef> [--escape-divider]

Names keep '/' unescaped (OpenROAD read_spef finds flat instances such as 'u_a/reg' by their full name);
--escape-divider writes 'u_a\\/reg' instead, for tools reading the flat routed netlist (PrimeTime).

<design.conn> is written by or/dump_conn.tcl (layers, vias, pin positions), <rc_corner.txt> by captable_rc.py.
Every routed wire segment becomes a resistor (R/um x length) with half of its capacitance (C/um x length) at each
end; a via is a resistor (R per cut / number of cuts).  Segments are split where another wire of the same net
starts on them (T junctions).  Pins attach to the nearest wire node of their net (a short M1 resistor for the
distance).  No coupling capacitance, no pin capacitance (the liberty has it).  Accuracy is limited by the RC
model of captable_rc.py; see pnr/README.md.
"""
import re
import sys
import time
from collections import defaultdict

KEYWORDS = {'NEW', 'ROUTED', 'FIXED', 'COVER', 'NOSHIELD', 'TAPER', 'TAPERRULE', 'STYLE', 'MASK', 'RECT',
            'VIRTUAL', 'SHAPE', 'USE', 'SOURCE', 'WEIGHT', 'PROPERTY', 'NONDEFAULTRULE', 'ORIGINAL', 'PATTERN',
            'ESTCAP', 'FIXEDBUMP', 'FREQUENCY', 'XTALK', 'SUBNET', 'VPIN', 'SHIELDNET', 'NOSHIELD'}


def read_conn(path):
    unit, layers, vias, pins, ports = 2000, {}, {}, defaultdict(list), defaultdict(list)
    with open(path) as f:
        for line in f:
            t = line.split()
            if not t:
                continue
            if t[0] == 'U':
                unit = int(t[1])
            elif t[0] == 'L':
                layers[t[1]] = (t[2], int(t[3]))
            elif t[0] == 'V':
                vias[t[1]] = (t[2], t[3], t[4], max(1, int(t[5])))
            elif t[0] == 'I':
                pins[t[1]].append((t[2], t[3], t[4], int(t[5]), int(t[6]), t[7], t[8]))
            elif t[0] == 'B':
                ports[t[1]].append((t[2], t[3], int(t[4]), int(t[5]), t[6]))
    return unit, layers, vias, pins, ports


def read_rc(path):
    wire, cut = {}, {}
    with open(path) as f:
        for line in f:
            t = line.split()
            if not t or t[0].startswith('#'):
                continue
            if t[1] == 'ROUTING':
                wire[t[0]] = (float(t[2]), float(t[3]))
            elif t[1] == 'CUT':
                cut[t[0]] = float(t[2])
    return wire, cut


def def_nets(path):
    """yield (name, use, token list of the routing statements) for every net of the NETS section"""
    with open(path) as f:
        data = f.read()
    m = re.search(r'^NETS \d+ ;(.*?)^END NETS', data, re.S | re.M)
    if not m:
        return
    for stmt in m.group(1).split(';'):
        tok = stmt.replace('(', ' ( ').replace(')', ' ) ').split()
        if not tok or tok[0] != '-':
            continue
        use = 'SIGNAL'
        if 'USE' in tok:
            use = tok[tok.index('USE') + 1]
        yield tok[1], use, tok


def unescape(n):
    return n.replace('\\', '')


ESC_DIV = False


def spef_name(n):
    out = []
    for ch in n:
        if ch.isalnum() or ch in '_[]' or (ch == '/' and not ESC_DIV):
            out.append(ch)
        else:
            out.append('\\' + ch)
    return ''.join(out)


def parse_route(tok, vias):
    """-> segments [(layer, (x1,y1), (x2,y2))], vias [(name, (x,y))]"""
    segs, vs = [], []
    i, n = 0, len(tok)
    # skip connection list up to the first routing keyword
    while i < n and not (tok[i] == '+' and i + 1 < n and tok[i + 1] in ('ROUTED', 'FIXED', 'COVER', 'NOSHIELD')):
        i += 1
    layer, last = None, None
    while i < n:
        t = tok[i]
        if t == '+':
            if i + 1 < n and tok[i + 1] in ('ROUTED', 'FIXED', 'COVER', 'NOSHIELD'):
                i += 2
                layer, last = tok[i], None
                i += 1
                continue
            break                                     # other net attribute: routing done
        if t == 'NEW':
            layer, last = tok[i + 1], None
            i += 2
            continue
        if t == '(':
            j = tok.index(')', i)
            vals = tok[i + 1:j]
            x = last[0] if vals[0] == '*' else int(vals[0])
            y = last[1] if vals[1] == '*' else int(vals[1])
            p = (x, y)
            if last is not None and p != last:
                segs.append((layer, last, p))
            last = p
            i = j + 1
            continue
        if t in ('RECT',):                            # patch: RECT ( dx1 dy1 dx2 dy2 ), ignored
            j = tok.index(')', i)
            i = j + 1
            continue
        if t == 'VIRTUAL':
            j = tok.index(')', i)
            vals = tok[i + 2:j]
            last = (int(vals[0]) if vals[0] != '*' else last[0], int(vals[1]) if vals[1] != '*' else last[1])
            i = j + 1
            continue
        if t in ('MASK', 'STYLE', 'TAPERRULE'):
            i += 2
            continue
        if t == 'TAPER':
            i += 1
            continue
        if t in vias and last is not None:
            vs.append((t, last))
            b, c, top, k = vias[t]
            layer = top if layer == b else b
            i += 1
            continue
        if re.match(r'^-?\d+(\.\d+)?$', t):          # explicit width after the layer name
            i += 1
            continue
        i += 1
    return segs, vs


def main():
    global ESC_DIV
    deff, connf, rcf, outf = sys.argv[1:5]
    ESC_DIV = '--escape-divider' in sys.argv[5:]
    unit, layers, vias, pins, ports = read_conn(connf)
    wire, cut = read_rc(rcf)
    rmin = 0.001
    top = re.search(r'^DESIGN\s+(\S+)\s*;', open(deff).read(4096), re.M).group(1)
    nets_out, port_dirs = [], {}
    for net in ports:
        for (p, d, x, y, l) in ports[net]:
            port_dirs[p] = d
    stats = {'nets': 0, 'unrouted': 0, 'res': 0}
    for dname, use, tok in def_nets(deff):
        if use in ('POWER', 'GROUND'):
            continue
        name = unescape(dname)
        segs, vs = parse_route(tok, vias)
        stats['nets'] += 1
        # nodes: (layer, x, y) -> id; split segments at nodes lying on them
        nodes = {}
        def nid(key):
            if key not in nodes:
                nodes[key] = len(nodes) + 1
            return nodes[key]
        pts = defaultdict(set)
        for (l, a, b) in segs:
            pts[l].add(a); pts[l].add(b)
        for (v, p) in vs:
            b_, c_, t_, k_ = vias[v]
            pts[b_].add(p); pts[t_].add(p)
        caps = defaultdict(float)
        res = []
        for (l, a, b) in segs:
            r_um, c_um = wire.get(l, (0.0, 0.0))
            if a[0] == b[0]:
                inner = sorted([q for q in pts[l] if q[0] == a[0] and min(a[1], b[1]) < q[1] < max(a[1], b[1])],
                               key=lambda q: abs(q[1] - a[1]))
            elif a[1] == b[1]:
                inner = sorted([q for q in pts[l] if q[1] == a[1] and min(a[0], b[0]) < q[0] < max(a[0], b[0])],
                               key=lambda q: abs(q[0] - a[0]))
            else:
                inner = []
            chain = [a] + inner + [b]
            for p, q in zip(chain, chain[1:]):
                ln = (abs(p[0] - q[0]) + abs(p[1] - q[1])) / float(unit)
                i1, i2 = nid((l, p)), nid((l, q))
                caps[i1] += c_um * ln / 2.0
                caps[i2] += c_um * ln / 2.0
                res.append((i1, i2, max(rmin, r_um * ln)))
        for (v, p) in vs:
            b_, c_, t_, k_ = vias[v]
            res.append((nid((b_, p)), nid((t_, p)), max(rmin, cut.get(c_, 1.0) / k_)))
        # pins: nearest node on the net (prefer the pin layer); star of tiny resistors if the net has no wires
        conn, pin_nodes = [], []
        r_m1 = wire.get('M1', (1.0, 0.0))[0]
        for (inst, pin, d, x, y, l, cell) in pins.get(name, []):
            pn = '%s:%s' % (spef_name(inst), spef_name(pin))
            conn.append('*I %s %s *D %s' % (pn, d, cell))
            pin_nodes.append((pn, x, y, l))
        for (p, d, x, y, l) in ports.get(name, []):
            pn = spef_name(p)
            conn.append('*P %s %s' % (pn, d))
            pin_nodes.append((pn, x, y, l))
        keys = list(nodes.keys())
        for (pn, x, y, l) in pin_nodes:
            if not keys:
                continue
            cand = [k for k in keys if k[0] == l] or keys
            k = min(cand, key=lambda k: abs(k[1][0] - x) + abs(k[1][1] - y))
            ln = (abs(k[1][0] - x) + abs(k[1][1] - y)) / float(unit)
            res.append((pn, nodes[k], max(rmin, r_m1 * ln)))
        if not keys:
            stats['unrouted'] += len(pin_nodes) > 1
            for (pn, x, y, l) in pin_nodes[1:]:
                res.append((pin_nodes[0][0], pn, rmin))
        sn = spef_name(name)
        def node(i):
            return i if isinstance(i, str) else '%s:%d' % (sn, i)
        total = sum(caps.values())
        lines = ['*D_NET %s %.6f' % (sn, total), '*CONN'] + conn + ['*CAP']
        k = 0
        for i in sorted(caps):
            if caps[i] > 0:
                k += 1
                lines.append('%d %s %.6f' % (k, node(i), caps[i]))
        lines.append('*RES')
        for k, (a, b, r) in enumerate(res, 1):
            lines.append('%d %s %s %.6f' % (k, node(a), node(b), r))
        stats['res'] += len(res)
        lines.append('*END\n')
        nets_out.append('\n'.join(lines))
    with open(outf, 'w') as f:
        f.write('*SPEF "IEEE 1481-1998"\n*DESIGN "%s"\n*DATE "%s"\n*VENDOR "qcnn"\n*PROGRAM "def2spef.py"\n'
                '*VERSION "1"\n*DESIGN_FLOW "NAME_SCOPE LOCAL" "PIN_CAP NONE"\n*DIVIDER /\n*DELIMITER :\n'
                '*BUS_DELIMITER [ ]\n*T_UNIT 1 NS\n*C_UNIT 1 FF\n*R_UNIT 1 OHM\n*L_UNIT 1 HENRY\n\n'
                % (top, time.strftime('%a %b %d %H:%M:%S %Y')))
        if port_dirs:
            f.write('*PORTS\n')
            for p, d in sorted(port_dirs.items()):
                f.write('%s %s\n' % (spef_name(p), d))
            f.write('\n')
        f.write('\n'.join(nets_out))
    print('def2spef: %(nets)d nets, %(res)d resistors, %(unrouted)d multi-pin nets without wires' % stats)


if __name__ == '__main__':
    main()
