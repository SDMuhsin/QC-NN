#!/usr/bin/env python3
"""impl/r8: impl/r7a/classify.py (net classes per hotspot window from a GRT checkpoint dump) with other windows.
    python3 -I classify_win.py DUMP GUIDE CONGRPT OBS OUTDIR
Windows (um, x0 y0 x1 y1): arraysw = over columns 0-3, bottom 1.3 mm of the array (M7-M9 only, R8 hot tiles);
junction = SW corner + bottom of the west strip.  Output files hot_<window>.txt (+ the r7a cut / whole-die tables)."""
import importlib.util
import os

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("r7a_classify", os.path.join(here, "..", "r7a", "classify.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.WIN = {"south": m.WIN["south"], "west": m.WIN["west"], "arraysw": (860.0, 1700.6, 2420.0, 3000.0), "junction": (0.0, 1000.0, 860.0, 2300.0)}
m.main()
