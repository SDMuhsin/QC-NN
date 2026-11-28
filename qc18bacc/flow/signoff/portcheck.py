#!/usr/bin/env python3
"""Port gate of a P&R netlist against its synthesis netlist (R62; common/block.sh blk_portcheck after every ICC2 outputs step).

    portcheck.py <syn.v> <pnr.v> <top>

Fails (exit 1) when the ports of the <top> module of <pnr.v> differ from those of <syn.v> in name, direction or bit
range (R103; before, only the total number of port bits was compared, so a renamed, re-directed or re-ranged port with
the same bit total passed), or on any 'assign <port> = <port>': a port-to-port assign means P&R removed a feedthrough
buffer, and the layout then merges the two ports into one net (R59: 4608 act -> act_o buffers removed, LVS saw 7748
instead of 12356 ports, ETM MEXT-97).  Prints one PORTCHECK line, then one PORTCHECK_DIFF line per differing port
(at most 10).
"""
import re
import sys

# (the keyword a whole word, R113; hunt round 14: 'output_buf ...' parsed as an output port 'buf ...')
DECL = re.compile(r'^\s*(input|output|inout)\b\s*(?:\[\s*(-?\d+)\s*:\s*(-?\d+)\s*\])?\s*(.*)$', re.S)
ASSIGN = re.compile(r'^\s*assign\s+(.+?)\s*=\s*(.+?)\s*$', re.S)


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


def bits(decl):
    return sum(1 if m is None else abs(m - l) + 1 for _, m, l in decl.values())


def show(d):
    return 'none' if d is None else d[0] + ('' if d[1] is None else f' [{d[1]}:{d[2]}]')


def base(sig):
    return re.sub(r'\s*\[[^\]]*\]$', '', sig.strip()).lstrip('\\')


def main():
    syn, pnr, top = sys.argv[1:4]
    body = top_module(pnr, top)
    ps, pp = ports(top_module(syn, top), syn), ports(body, pnr)
    p2p = [a.group(0).strip() for a in (ASSIGN.match(s) for s in body.split(';'))
           if a and base(a.group(1)) in pp and base(a.group(2)) in pp]
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
