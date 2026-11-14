#!/usr/bin/env python3
"""R5d step 1: group the violating endpoints of impl/r5d/hist.tcl by functional class (instance-name prefix).
   python3 qc18bacc/impl/r5d/hist.py viol_<corner>_p<P>.txt   -> table: class, count, worst slack, worst path split"""
import re, sys
from collections import OrderedDict

CLS = [  # (name, start regex, end regex)  first match wins
    ('act feedthrough (act -> act_o, IO)', r'^act\[', r'^act_o\['),
    ('act -> PE S0 (IO)',                 r'^act\[', r''),
    ('s_rd / south in -> fused u_rin (IO)', r'^(s_rd|w_r|pf|pw|p_ld|w_ld|f_|w_)', r'u_lf/u_rin'),
    ('south in -> other (IO)',            r'^(s_rd|w_r|pf|pw|p_ld|w_ld|f_|w_)', r''),
    ('north in (cd / ctl / t2, IO)',      r'^(cd|ctl|t2)\[', r''),
    ('reg -> south out (IO)',             r'', r'^(f_y|f_b|w_y|w_b|b2|f_vld_o|w_vld_o)'),
    ('dec -> BR nnw_q (cdr -> u_br)',     r'cdr_reg|ctlr_reg', r'u_br/nnw_q'),
    ('dec -> BR c_q (cdr -> u_br)',       r'cdr_reg|ctlr_reg', r'u_br/'),
    ('BR -> PE popcount / S1',            r'u_br/', r'u_pe/'),
    ('PE internal (S1 -> S2 acc)',        r'u_pe/', r'u_pe/'),
    ('PE shadow -> fused lane u_rin',     r'u_pe/', r'u_lf/'),
    ('PE shadow -> wide lane',            r'u_pe/', r'u_lw/'),
    ('fused lane stages',                 r'u_lf/', r'u_lf/'),
    ('wide lane stages',                  r'u_lw/', r'u_lw/'),
    ('param bank -> fused lane',          r'u_pbf/', r''),
    ('param bank -> wide lane',           r'u_pbw/', r''),
    ('other',                             r'', r''),
]

def main(fn):
    g = OrderedDict((c[0], []) for c in CLS)
    for ln in open(fn):
        if ln.startswith('#') or not ln.strip(): continue
        f = ln.split()
        r = dict(slack=float(f[0]), s=f[1], e=f[2], wire=float(f[3]), cell=float(f[4]), n=int(f[5]),
                 cap=float(f[6]), net=f[7], buf=float(f[8]) if len(f) > 8 else 0.0, nb=int(f[9]) if len(f) > 9 else 0)
        for name, rs, re_ in CLS:
            if re.search(rs, r['s']) and re.search(re_, r['e']):
                g[name].append(r); break
    tot = sum(len(v) for v in g.values())
    print(f'{fn}: {tot} violating endpoints')
    print('| class | endpoints | worst slack ns | worst path: start -> end | cells (buf) | logic / buf / wire ns | max net C pF |')
    print('|---|---|---|---|---|---|---|')
    for k, v in sorted(g.items(), key=lambda kv: -len(kv[1])):
        if not v: continue
        w = min(v, key=lambda r: r['slack'])
        print(f"| {k} | {len(v)} | {w['slack']:.3f} | `{w['s']}` -> `{w['e']}` | {w['n']} ({w['nb']}) | "
              f"{w['cell'] - w['buf']:.2f} / {w['buf']:.2f} / {w['wire']:.2f} | {w['cap']:.3f} |")

if __name__ == '__main__':
    for a in sys.argv[1:]: main(a)
