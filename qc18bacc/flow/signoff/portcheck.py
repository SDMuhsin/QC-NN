#!/usr/bin/env python3
"""Port gate of a P&R netlist against its synthesis netlist (R62; common/block.sh blk_portcheck after every ICC2 outputs step).

    portcheck.py <syn.v> <pnr.v> <top>

Fails (exit 1) when the ports of the <top> module of <pnr.v> differ from those of <syn.v> in name, direction or bit
range (R103; before, only the total number of port bits was compared, so a renamed, re-directed or re-ranged port with
the same bit total passed), or on any 'assign <port> = <port>': a port-to-port assign means P&R removed a feedthrough
buffer, and the layout then merges the two ports into one net (R59: 4608 act -> act_o buffers removed, LVS saw 7748
instead of 12356 ports, ETM MEXT-97).  Concatenations count bit by bit (R114; hunt round 15 on f8f6eee:
'assign {a, b} = {c, d}' passed): both sides are expanded to bits (ports and declared wires by their ranges, part /
bit selects, sized constants), paired from the LSB, and any port bit assigned from a port bit fails; an assign whose
sides cannot be expanded to equal widths joins every bit it names.  Chains count too (R115): two port bits joined
through wires by several assigns ('assign w = a; assign b = w;') fail, and so does each assignment of a statement that
lists several ('assign a = b, c = d;').  Prints one PORTCHECK line (port_to_port_assigns = the groups of port bits the
assigns join), then one PORTCHECK_DIFF line per differing port (at most 10).
"""
import re
import sys

# (the keyword a whole word, R113; hunt round 14: 'output_buf ...' parsed as an output port 'buf ...')
DECL = re.compile(r'^\s*(input|output|inout)\b\s*(?:\[\s*(-?\d+)\s*:\s*(-?\d+)\s*\])?\s*(.*)$', re.S)
ASSIGN = re.compile(r'^\s*assign\b(.*)$', re.S)
WIRE = re.compile(r'^\s*wire\b\s*(?:\[\s*(-?\d+)\s*:\s*(-?\d+)\s*\])?\s*(.*)$', re.S)
ELEM = re.compile(r"^\\?([^\s\[\]{}]+)\s*(?:\[\s*(-?\d+)\s*(?::\s*(-?\d+)\s*)?\])?$")
CONST = re.compile(r"^(\d+)\s*'\s*[sS]?[bBoOdDhH]\s*[0-9a-fA-FxXzZ_?]+$")


def top_module(path, top):
    with open(path) as f:
        text = f.read()
    m = re.search(r'^\s*module\s+' + re.escape(top) + r'\b(.*?)^\s*endmodule', text, re.S | re.M)
    if not m:
        sys.exit(f'PORTCHECK FAIL no module {top} in {path}')
    return re.sub(r'//[^\n]*', '', m.group(1))


def ports(body, path):
    """{base name: (direction, msb, lsb)} of the port declarations of a module body (msb = lsb = None: a scalar)"""
    decl = {}
    for stmt in body.split(';'):
        d = DECL.match(stmt)
        if not d:
            continue
        r = (int(d.group(2)), int(d.group(3))) if d.group(2) else (None, None)
        for n in d.group(4).split(','):
            n = n.strip().lstrip('\\')
            if n:
                if n in decl:
                    sys.exit(f'PORTCHECK FAIL port {n} declared twice in {path}')
                decl[n] = (d.group(1),) + r
    return decl


def wires(body):
    """{name: (msb, lsb)} of the wire declarations of a module body (scalars: (None, None))"""
    w = {}
    for stmt in body.split(';'):
        d = WIRE.match(stmt)
        if d:
            for n in d.group(3).split(','):
                if n.strip():
                    w[n.strip().lstrip('\\')] = (int(d.group(1)), int(d.group(2))) if d.group(1) else (None, None)
    return w


def expand(side, ranges):
    """the bits of one assign side, MSB first: (name, bit) per bit (bit None: a scalar; name None: a constant bit);
    None when it cannot be expanded (unknown construct, replication)"""
    s = side.strip()
    items = [x.strip() for x in s[1:-1].split(',')] if s.startswith('{') and s.endswith('}') else [s]
    out = []
    for x in items:
        c = CONST.match(x)
        if c:
            out += [(None, None)] * int(c.group(1))
            continue
        e = ELEM.match(x)
        if not e or '{' in x:
            return None
        n, a, b = e.group(1), e.group(2), e.group(3)
        m, l = ranges.get(n, (None, None))
        if a is None and m is None:
            out.append((n, None))
        elif a is None:
            step = -1 if m >= l else 1
            out += [(n, i) for i in range(m, l + step, step)]
        else:
            a = int(a); b = a if b is None else int(b)
            step = -1 if a >= b else 1
            out += [(n, i) for i in range(a, b + step, step)]
    return out


def top_split(s, sep):
    """s split at the character sep outside (), [], {} and escaped identifiers (backslash up to white space)"""
    out, cur, depth, esc = [], [], 0, False
    for ch in s:
        if esc:
            esc = not ch.isspace()
        elif ch == '\\':
            esc = True
        elif ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        elif ch == sep and depth == 0:
            out.append(''.join(cur)); cur = []
            continue
        cur.append(ch)
    return out + [''.join(cur)]


def assignments(body):
    """(lhs, rhs, text) of every assignment of the module's assign statements ('assign a = b, c = d;' is two, R115);
    rhs None when the text is not one '<lhs> = <rhs>'"""
    for st in body.split(';'):
        a = ASSIGN.match(st)
        for x in top_split(a.group(1), ',') if a else []:
            lr = top_split(x, '=')
            yield (lr[0], lr[1], x.strip()) if len(lr) == 2 else (x, None, x.strip())


def port_groups(body, pp, ranges):
    """the groups of two or more port bits the assigns connect, also through wires (R115; round-16 hunt: 'assign w = a;
    assign b = w;' passed): bits joined bit by bit where both sides expand to equal widths (constant bits join nothing),
    else every bit of every identifier of the assignment joined (unparsed: conservative)"""
    up = {}

    def find(x):
        while up.setdefault(x, x) != x:
            up[x] = up[up[x]]; x = up[x]
        return x

    def join(xs):
        for x in xs[1:]:
            up[find(x)] = find(xs[0])
    names = lambda s: sorted(set(re.findall(r"(?<!['\w$\\])\\?([A-Za-z_][\w$]*)", s)))   # (not the base letter of a constant)
    for lhs, rhs, _ in assignments(body):
        a, b = expand(lhs, ranges), (None if rhs is None else expand(rhs, ranges))
        if a is None or b is None or len(a) != len(b):
            join([x for n in names(lhs + ' ' + (rhs or '')) for x in expand(n, ranges)])
        else:
            for x, y in zip(a, b):
                if x[0] is not None and y[0] is not None:
                    join([x, y])
    g = {}
    for x in list(up):
        if x[0] in pp:
            g.setdefault(find(x), []).append(x)
    return [sorted(v, key=str) for v in g.values() if len(v) > 1]


def bits(decl):
    return sum(1 if m is None else abs(m - l) + 1 for _, m, l in decl.values())


def show(d):
    return 'none' if d is None else d[0] + ('' if d[1] is None else f' [{d[1]}:{d[2]}]')


def main():
    syn, pnr, top = sys.argv[1:4]
    body = top_module(pnr, top)
    ps, pp = ports(top_module(syn, top), syn), ports(body, pnr)
    ranges = dict(wires(body), **{n: (m, l) for n, (_, m, l) in pp.items()})
    p2p = [' = '.join(n if i is None else f'{n}[{i}]' for n, i in g) for g in port_groups(body, pp, ranges)]
    diff = [f'PORTCHECK_DIFF {n}: syn {show(ps.get(n))} pnr {show(pp.get(n))}'
            for n in sorted(set(ps) | set(pp)) if ps.get(n) != pp.get(n)]
    ok = bool(ps) and not diff and not p2p
    print(f'PORTCHECK {"OK" if ok else "FAIL"} {top} ports syn {len(ps)} pnr {len(pp)} port_bits syn {bits(ps)} pnr {bits(pp)}'
          f' differing_ports {len(diff)} port_to_port_assigns {len(p2p)}' + (f' first: {p2p[0]}' if p2p else ''))
    for d in diff[:10]:
        print(d)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
