#!/usr/bin/env python3
"""R26: repair attribution between two area26.tcl dumps (results/r26.md).
    python3 -I rep26.py <inst_a.txt> <inst_b.txt>
added cells by name prefix (hold / wire fanout max_length load_slew max_cap split rebuffer gain / clkbuf cts / other),
removed, resized (same name, other master); areas in um2, pins = signal ITerms."""
import re, sys
from collections import Counter
def rd(f):
    d = {}
    for ln in open(f):
        t = ln.split(); d[t[0]] = (t[1], float(t[2]), int(t[3]))
    return d
A, B = rd(sys.argv[1]), rd(sys.argv[2])
sa = lambda D: (len(D), sum(v[1] for v in D.values()), sum(v[2] for v in D.values()))
def pref(n):
    b = n.split("/")[-1]
    m = re.match(r"^(hold|wire|fanout|max_length|load_slew|max_cap|split|rebuffer|gain|clkbuf|clkload|cts|delay|place)", b)
    return m.group(1) if m else "other"
N, AR, P = Counter(), Counter(), Counter()
for n, v in B.items():
    if n not in A: k = pref(n); N[k] += 1; AR[k] += v[1]; P[k] += v[2]
rem = [n for n in A if n not in B]; rsz = [n for n in B if n in A and A[n][0] != B[n][0]]
print("R26_REP a %d inst %.0f um2 %d pins -> b %d inst %.0f um2 %d pins" % (*sa(A), *sa(B)))
for k, v in AR.most_common(): print("R26_REP added %-10s %7d inst %+10.0f um2 %+8d pins" % (k, N[k], v, P[k]))
print("R26_REP removed %d inst %+.0f um2; resized %d inst %+.0f um2" % (len(rem), -sum(A[n][1] for n in rem), len(rsz),
      sum(B[n][1] - A[n][1] for n in rsz)))
