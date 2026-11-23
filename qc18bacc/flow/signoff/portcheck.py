#!/usr/bin/env python3
"""Port gate of a P&R netlist against its synthesis netlist (R62; blocks/col/run.sh after every ICC2 outputs step).

    portcheck.py <syn.v> <pnr.v> <top>

Fails (exit 1) when the <top> module of <pnr.v> has a different number of port bits than <syn.v>, or any
'assign <port> = <port>': a port-to-port assign means P&R removed a feedthrough buffer, and the layout then merges the
two ports into one net (R59: 4608 act -> act_o buffers removed, LVS saw 7748 instead of 12356 ports, ETM MEXT-97).
Prints one PORTCHECK line.
"""
import re
import sys

DECL = re.compile(r'^\s*(input|output|inout)\s*(?:\[\s*(-?\d+)\s*:\s*(-?\d+)\s*\])?\s*(.*)$', re.S)
ASSIGN = re.compile(r'^\s*assign\s+(.+?)\s*=\s*(.+?)\s*$', re.S)


def top_module(path, top):
    with open(path) as f:
        text = f.read()
    m = re.search(r'^\s*module\s+' + re.escape(top) + r'\b(.*?)^\s*endmodule', text, re.S | re.M)
    if not m:
        sys.exit(f'PORTCHECK FAIL no module {top} in {path}')
    return re.sub(r'//[^\n]*', '', m.group(1))


def ports(body):
    """{base name: bit count} of the port declarations of a module body"""
    bits = {}
    for stmt in body.split(';'):
        d = DECL.match(stmt)
        if not d:
            continue
        w = abs(int(d.group(2)) - int(d.group(3))) + 1 if d.group(2) else 1
        for n in d.group(4).split(','):
            n = n.strip().lstrip('\\')
            if n:
                bits[n] = w
    return bits


def base(sig):
    return re.sub(r'\s*\[[^\]]*\]$', '', sig.strip()).lstrip('\\')


def main():
    syn, pnr, top = sys.argv[1:4]
    ps, pp = ports(top_module(syn, top)), ports(top_module(pnr, top))
    body = top_module(pnr, top)
    p2p = [a.group(0).strip() for a in (ASSIGN.match(s) for s in body.split(';'))
           if a and base(a.group(1)) in pp and base(a.group(2)) in pp]
    ns, np = sum(ps.values()), sum(pp.values())
    ok = ns == np and not p2p
    print(f'PORTCHECK {"OK" if ok else "FAIL"} {top} port_bits syn {ns} pnr {np} port_to_port_assigns {len(p2p)}'
          + (f' first: {p2p[0]}' if p2p else ''))
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
