#!/usr/bin/env python3
"""Wire vs cell delay on the first data path of a timing report (OpenROAD report_checks -fields input_pins, or
PrimeTime report_timing -input_pins), for results/pnr_core.md.
  python3 wire_share.py <report> [<report> ...]
A data-path row whose instance differs from the previous row's instance (or a port row) is reached over a net:
its increment is net (wire RC) delay; a row on the same instance is a cell arc, counted as a repeater when the
instance was inserted by the P&R repair (REP names: wireN, splitN, ...), else as logic.  The launch clock section (up to the
startpoint clock pin) is excluded; the data path starts at the startpoint's CP / clock pin and ends at the endpoint."""
import re, sys

ROW = re.compile(r'^\s*(?:(?:\d+\s+)?(?:-?\d+\.\d+\s+)*?(?P<a_inc>-?\d+\.\d+)\s+(?P<a_tim>-?\d+\.\d+)\s+[\^v]\s+(?P<a_pin>\S+)\s*(?P<a_cell>\(\S+\))?'
                 r'|(?P<b_pin>\S+)\s+(?P<b_cell>\(\S+\))?(?:\s+-?\d+\.\d+)*?\s+(?P<b_inc>-?\d+\.\d+)\s*[&*]?\s+(?P<b_tim>-?\d+\.\d+)\s*[&*]?\s+[rf])\s*$')

# buffers inserted by OpenROAD's repair_design / repair_timing (long-wire repeaters, split loads, hold): wire cost
REP = re.compile(r'^(wire|max_length|split|rebuffer|max_cap|load_slew|hold|place|cts_|clkbuf|repeater)\d*')

def inst(pin):
    return pin.rsplit('/', 1)[0] if '/' in pin else '<port>' + pin

def one(path):
    with open(path) as f:
        lines = f.read().split('\n')
    sp = ep = None
    for l in lines:
        m = re.match(r'\s*Startpoint:\s*(\S+)', l)
        if m and sp is None: sp = m.group(1)
        m = re.match(r'\s*Endpoint:\s*(\S+)', l)
        if m and ep is None: ep = m.group(1)
    rows = []
    started = False
    for l in lines:
        if rows and ('data arrival time' in l):
            break
        m = ROW.match(l)
        if not m:
            continue
        pin = m.group('a_pin') or m.group('b_pin')
        inc = float(m.group('a_inc') or m.group('b_inc'))
        cell = m.group('a_cell') or m.group('b_cell') or ''
        if not started:
            # data path starts at the startpoint clock pin (register) or the input port
            if sp and (pin.startswith(sp + '/') or pin == sp) and (cell or '/' not in pin):
                started = True
            else:
                continue
        rows.append((pin, cell, inc))
    wire = cell_d = rep = 0.0
    nets = nrep = 0
    for i, (pin, cell, inc) in enumerate(rows):
        if i == 0:
            continue
        if inst(pin) != inst(rows[i - 1][0]) or pin.startswith('<port>'):
            wire += inc; nets += 1
        elif REP.match(inst(pin).rsplit('/', 1)[-1]):
            rep += inc; nrep += 1
        else:
            cell_d += inc
    slack = None
    for l in lines:
        m = re.search(r'(-?\d+\.\d+)\s+slack', l) or re.search(r'slack\s*\(\w+\)\s+(-?\d+\.\d+)', l)
        if m: slack = float(m.group(1)); break
    tot = wire + cell_d + rep
    print(f'{path}: start {sp} end {ep} slack {slack} data_path_ns {tot:.3f} logic_cell_ns {cell_d:.3f} '
          f'net_ns {wire:.3f} repeater_ns {rep:.3f} ({nrep} P&R buffers) wire_share_net {wire / tot if tot else 0:.3f} '
          f'wire_share_net+repeaters {(wire + rep) / tot if tot else 0:.3f} stages {nets}')

for p in sys.argv[1:]:
    one(p)
