#!/usr/bin/env python3
"""Sanity gate of a block ETM .lib against the netlist reference written in the same PrimeTime session
(signoff/etm/etm.tcl -> signoff/pt/common.tcl qb_etm_ref: <stem>_ref.txt beside <stem>.lib; clock period P, the design
max_transition, each port's netlist capacitance).  Exit 1 on any of:
  values     a table value or index that is not a finite number, an index that is negative or not increasing, a
             transition value <= 0, or any table value (delay, transition, setup / hold / recovery / removal, pulse
             width) with |v| >= P.  Why P: the blocks are single-cycle, so a boundary setup or hold >= P cannot be met by
             any input timing, a clk->out >= P cannot be captured in the next cycle and a slew >= P is no signal: such a
             value is a sign-off failure or garbage (R43's driving-cell outlier: act[2911] hold 7.26 ns at P 6.5 ns).
             R98 [M], why not the former fixed 3 ns: every value beyond 3 ns in the column's r97x ETMs (59 ss, 1230 wcl,
             13 wcl_rcw) is a setup_rising table of an s_rd bit at all 25 index points (wcl max 3.615 ns at data / clk
             slew 0.5 / 0); PrimeTime on the netlist gives the same path s_rd[306] -> register at slack +1.44 ns, data
             delay 4.227 - capture latency 0.751 + library setup 0.039 = 3.515 ns vs the ETM 3.485 at (0.5, 0.5).
             Largest |v| (col P 6.5 / rgr P 2.5): 3.615 / 0.849 ns.
  capacitance  a pin whose capacitance is not the reference's (input: port net total capacitance, output: port net
             wire capacitance, within the 6-decimal rounding), or pin sets that differ.  R98 [M], why not the former
             0.065 pF: the 127-352 r97x pins above it are the act feedthrough inputs (long nets, <= 0.079 pF) and the
             b2 / f_y / b2_vld / f_b / act_o outputs (wire <= 0.216 pF); PrimeTime's port nets equal all 12354 pins.
  max_transition  an input pin without it or with another value than the reference's (R63: the ETM context
             set_input_transition 0 gave 0 on all data inputs; it must be the context slew, signoff/pt/common.tcl
             qb_etm_context).
  arcs       (R111; hunt round 13 on 1940fd4: an input that lost its setup / hold arc, or an output without a clock -> out
             arc, passed) every input that is not a clock pin (clock : true) has a setup_* and a hold_* arc related to a
             clock pin, every output a rising_edge / falling_edge arc related to a clock pin, a max and a min one
             (min_delay_flag), unless signoff/etm/arc_except.txt declares it, with its reason: untimed inputs (rst_n),
             feedthrough outputs (the column's act_o[b], whose required arcs are then the max and min combinational arcs
             from its declared input act[b]).  [M] rgr rg5cf6581a ss:
             100 data inputs setup + hold, 18 outputs clock -> out (max + min), rst_n untimed; column r100 ss: 6957 data inputs, 787
             outputs, 4608 act_o feedthroughs, rst_n.
  no table values, or no reference.
Not detected: a timing table copied from another pin with the same capacitance (a timing comparison against PrimeTime
per port is not exact: R98 [M] 30 ps of 3.5 ns on s_rd[306], derate / slew handling of extract_model).
usage: etmcheck.py <etm.lib>"""
import math, os, re, sys
src = sys.argv[1]
if not src.endswith('.lib'): sys.exit('etmcheck.py: not a .lib: ' + src)
ref = src[:-4] + '_ref.txt'
CAP_TOL = 1.5e-6   # pF: both files round the same PrimeTime value to 6 decimals
try:
    with open(ref) as f: head, *rows = f.read().splitlines()
    P, MT = (float(x) for x in re.fullmatch(r'QB_ETM_REF period (\S+) max_transition (\S+)', head).groups())
    rcap = {p: float(c) for p, _, c in (r.split() for r in rows)}
except (OSError, ValueError, AttributeError) as e:
    print('ETMCHECK %s FAIL no reference %s (%s)' % (src, ref, e)); sys.exit(1)
t = open(src).read()
def nums(s): return [float(x) for q in re.findall(r'"([^"]*)"', s) for x in q.split(',')]
pins = list(re.finditer(r'\n\s*pin\s*\(\s*"?([^")]+)"?\s*\)\s*\{', t))
bad = {'values': [], 'capacitance': [], 'max_transition': [], 'arcs': []}; n = 0; vmax = (0.0, ''); seen = set()
def flag(k, what): bad[k].append(what)
# the declared arc exceptions: (kind, port regexp, related pin template, reason)
EXC = []
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'arc_except.txt')) as f:
    for l in f:
        if l.startswith('#') or not l.strip(): continue
        x = re.fullmatch(r'(untimed|feedthrough) (\S+) (\S+) -- (\S.*)', l.strip())
        if x: EXC.append(x.groups())
        else: flag('arcs', 'arc_except.txt line not "<untimed|feedthrough> <port regexp> <related pin> -- <reason>": ' + l.strip())
def arc(a):   # (timing_type, related_pin, min) of a timing group's text (min: a min_delay_flag arc, the early delays)
    ty, rp = re.search(r'timing_type\s*:\s*(\w+)', a), re.search(r'related_pin\s*:\s*"([^"]*)"', a)
    return ty.group(1) if ty else '', rp.group(1) if rp else '', bool(re.search(r'min_delay_flag\s*:\s*true\s*;', a))
pin = {}   # pin -> (direction, clock pin, [(timing_type, related_pin, min)])
for i, m in enumerate(pins):
    p = m.group(1); body = t[m.end():pins[i + 1].start() if i + 1 < len(pins) else len(t)]; seen.add(p)
    d = re.search(r'^\s*direction\s*:\s*"?(\w+)', body, re.M); c = re.search(r'^\s*capacitance\s*:\s*(\S+?)\s*;', body, re.M)
    pin[p] = (d.group(1) if d else '', bool(re.search(r'^\s*clock\s*:\s*true\s*;', body, re.M)),
              [arc(a) for a in re.findall(r'timing\s*\(\s*\)\s*\{(.*?)\}\s*/\* end of arc', body, re.S)])
    if p not in rcap: flag('capacitance', p + ' not in the reference')
    elif not c or not abs(float(c.group(1)) - rcap[p]) <= CAP_TOL:
        flag('capacitance', '%s %s vs netlist %.6f' % (p, c.group(1) if c else 'none', rcap[p]))
    if d and d.group(1) == 'input':
        v = re.search(r'^\s*max_transition\s*:\s*(\S+?)\s*;', body, re.M)
        if not v or not abs(float(v.group(1)) - MT) <= 1e-6: flag('max_transition', '%s %s' % (p, v.group(1) if v else 'none'))
    for a in re.finditer(r'timing\s*\(\s*\)\s*\{(.*?)\}\s*/\* end of arc', body, re.S):
        tt = re.search(r'timing_type\s*:\s*(\w+)', a.group(1)).group(1)
        for g, tb in re.findall(r'(\w+)\s*\(\s*\w+\s*\)\s*\{(.*?)\}', a.group(1), re.S):
            w = '%s %s %s' % (p, tt, g)
            for ix in re.findall(r'index_\d\s*\((.*?)\)\s*;', tb, re.S):
                x = nums(ix)
                if not all(math.isfinite(y) and y >= 0 for y in x) or any(b <= a for a, b in zip(x, x[1:])):
                    flag('values', '%s index %s' % (w, ','.join('%g' % y for y in x)))
            v = re.search(r'values\s*\((.*?)\)\s*;', tb, re.S)
            if not v: continue
            x = nums(v.group(1)); n += len(x)
            if not all(math.isfinite(y) and abs(y) < P for y in x) or ('transition' in g and min(x) <= 0):
                flag('values', '%s %s' % (w, max(x, key=lambda y: abs(y) if math.isfinite(y) else math.inf)))
            vmax = max(vmax, (max(abs(y) for y in x), w), key=lambda z: z[0] if math.isfinite(z[0]) else math.inf)
miss = sorted(set(rcap) - seen)
if miss: flag('capacitance', '%d reference ports without a pin (%s)' % (len(miss), ' '.join(miss[:3])))
# arcs per pin: data inputs setup + hold, outputs clock -> out, but the clock pins and the declared exceptions
clocks = {p for p, (_, ck, _) in pin.items() if ck}; cnt = dict.fromkeys(('clock', 'data_in', 'untimed', 'clock_out', 'feedthrough'), 0)
def exception(p, kind):   # (match, related pin template) of the first declared exception of <kind> matching pin p, or None
    return next(((x, rel) for k, rx, rel, _ in EXC if k == kind for x in [re.fullmatch(rx, p)] if x), None)
for p, (d, ck, arcs) in pin.items():
    if d not in ('input', 'output', 'inout'): flag('arcs', '%s direction %s' % (p, d or 'none')); continue
    if d != 'output':
        if ck: cnt['clock'] += 1
        elif exception(p, 'untimed'): cnt['untimed'] += 1
        else:
            m = [k for k in ('setup', 'hold') if not any(tt.startswith(k + '_') and rp in clocks for tt, rp, _ in arcs)]
            if m: flag('arcs', '%s (input) no %s arc from a clock pin' % (p, ' / '.join(m)))
            else: cnt['data_in'] += 1
    if d != 'input':   # a max and a min (min_delay_flag) delay arc each
        ft = exception(p, 'feedthrough')
        if ft:
            r = ft[0].expand(ft[1])
            m = [k for k, mn in (('max', False), ('min', True)) if ('combinational', r, mn) not in arcs]
            if m: flag('arcs', '%s (declared feedthrough) no %s combinational arc from %s' % (p, ' / '.join(m), r))
            else: cnt['feedthrough'] += 1
        else:
            m = [k for k, mn in (('max', False), ('min', True)) if not any(tt in ('rising_edge', 'falling_edge') and rp in clocks and x == mn for tt, rp, x in arcs)]
            if m: flag('arcs', '%s (output) no %s clock -> out arc' % (p, ' / '.join(m)))
            else: cnt['clock_out'] += 1
print('ETMCHECK %s reference %s: period %.3f ns, max_transition %.3f ns, %d ports' % (src, ref, P, MT, len(rcap)))
print('ETMCHECK %d pins, %d table values, largest |value| %.3f ns (%s), limit |value| < period %.3f' % (len(pins), n, vmax[0], vmax[1], P))
print('ETMCHECK arcs: %s (signoff/etm/arc_except.txt: %d exceptions)' % (', '.join('%s %d' % kv for kv in cnt.items()), len(EXC)))
for k, l in bad.items(): print('ETMCHECK %-14s %d bad %s' % (k, len(l), '; '.join(l[:3])))
fail = ['%s %d' % (k, len(l)) for k, l in bad.items() if l] + (['no table values'] if not n else [])
print('ETMCHECK %s %s' % (src, 'FAIL ' + ', '.join(fail) if fail else 'PASS'))
sys.exit(1 if fail else 0)
