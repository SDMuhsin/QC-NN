#!/usr/bin/env python3
"""R5b (results/r5b.md; was impl/r5b/etm_ins.py, restored in R48): OpenROAD copy of a block ETM (PrimeTime extract_model)
with the block's clock-tree insertion delay as liberty max / min_clock_tree_path arcs on the clock pin (the R5a IO budget
convention: the top tree is balanced with the block's internal sinks).  Values: the routed block's own PT latencies of
that corner (signoff/pt/common.tcl qb_pt_lat -> <run>/out/clk_lat_<c>.txt "p50 min max"; R36 used hand-copied constants).
usage: etm_ins.py <in.lib> <out.lib> <max_ns> <min_ns> [clk]"""
import sys
src, dst, mx, mn = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
clk = sys.argv[5] if len(sys.argv) > 5 else 'clk'
arc = '''	timing () {
		related_pin : "%s" ;
		timing_type : %s_clock_tree_path ;
		timing_sense : positive_unate ;
		cell_rise( scalar ) { values ( "%.4f" ); }
		cell_fall( scalar ) { values ( "%.4f" ); }
	}
'''
end = '} /* end of pin %s */' % clk
t = open(src).read()
assert t.count(end) == 1, 'clock pin end marker not found once'
t = t.replace(end, arc % (clk, 'max', mx, mx) + arc % (clk, 'min', mn, mn) + end)
open(dst, 'w').write(t)
print('ETM_INS %s max %.3f min %.3f' % (dst, mx, mn))
