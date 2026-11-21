# R38: run a KLayout batch script ("klayout -b -r s.py -rd k=v ...") with the klayout Python wheel (tau6 has no klayout
# binary).  python3 klrun.py -b -r <script.py> [-rd k=v ...]
import sys, runpy
a = sys.argv[1:]; g = {}; script = None; i = 0
while i < len(a):
    if a[i] == '-r': script = a[i + 1]; i += 2
    elif a[i] == '-rd': k, v = a[i + 1].split('=', 1); g[k] = v; i += 2
    else: i += 1
import pya
g['pya'] = pya
runpy.run_path(script, init_globals=g, run_name='__main__')
