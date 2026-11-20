#!/usr/bin/env python3
"""R31 (results/r31.md): impl/r21/cuts21.py with a per-layer budget adjustment (the R22 gate at the corrected capacity).
    R31_BADJ="M2-M3 0.6 M4 0.25 M5-M9 0.10" python3 -I cuts31.py <cuts21.py arguments ...>
cuts21.py's capacity line CAP = raw * (1 - ADJ) * KC takes the layer's R31_BADJ value instead of the scalar ADJ
(layers not named keep ADJ); everything else is cuts21.py as is (executed from its source, not copied)."""
import os
import sys
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "r21", "cuts21.py")
src = open(p).read()
old = "CAP[L] = (raw * (1 - ADJ) * KC[L])"
assert src.count(old) == 1
src = src.replace(old, "CAP[L] = (raw * (1 - adjspec(os.environ['R31_BADJ']).get(L, ADJ)) * KC[L])")
sys.argv[0] = p
exec(compile(src, p, "exec"), {"__name__": "__main__", "__file__": p})
