#!/usr/bin/env python3
"""Turn the bender compile script of the sim/ Questa testbench (target/snitch_cluster/work-vsim/
compile.vsim.tcl, made by sim/build_hw.sh vsim) into the gate-level one, compiled into ./work:

  * generated/snitch_cluster_wrapper.sv (package + RTL wrapper) -> its package only, so the TB
    (testharness, tb_memory_axi) keeps snitch_cluster_pkg and the RTL wrapper is gone;
  * then the TSMC65 cell models, the ARM macro models and the DC netlist (top module
    snitch_cluster_wrapper, same port widths, packed structs bind to the flat vectors);
  * gls_trace.sv (retire trace + X check) as a second top level.
Every other block (RTL deps, TB, fesvr DPI) is kept as is.  Mode rtl keeps the RTL wrapper and
only adds gls_trace.sv (validation of the monitor against the upstream tracer).

  * sdf only: target/common/test/tb_bin.sv -> tb_bin_sdf.sv next to the output (same TB, clock
    period TCK = <tck_ps>, since the netlist does not run at the TB's 1 GHz at tt).

  mk_compile.py <compile.vsim.tcl> <rtl|zd|sdf> <pkg.sv> <cells.v> <netlist.v> <trace.sv> <tck_ps> <macro.v>... > out.tcl
"""
import sys

import os
import re

if len(sys.argv) < 9:
    sys.exit(__doc__)
src, mode, pkg, cells, netlist, trace, tck, *macros = sys.argv[1:]
text = open(src).read().replace("-work work-vsim/", "-work work")
if mode != "rtl":
    wrapper = '"$ROOT/target/snitch_cluster/generated/snitch_cluster_wrapper.sv"'
    if text.count(wrapper) != 1:
        sys.exit("expected exactly one snitch_cluster_wrapper.sv in " + src)
    text = text.replace(wrapper, f'"{pkg}"')
if mode == "sdf":
    root = re.search(r'^set ROOT "(.*)"', text, re.M)[1]
    tb = open(f"{root}/target/common/test/tb_bin.sv").read()
    if tb.count("localparam TCK = 1ns;") != 1:
        sys.exit("tb_bin.sv: TCK definition not found")
    tbs = os.path.join(os.path.dirname(os.path.abspath(trace)), "tb_bin_sdf.sv")
    open(tbs, "w").write(tb.replace("localparam TCK = 1ns;", f"localparam TCK = {int(tck)}ps;"))
    text = text.replace('"$ROOT/target/common/test/tb_bin.sv"', f'"{tbs}"')

q = lambda fs: " ".join(f'"{f}"' for f in fs)
add = "# ---- gate-level part (impl/snitch_cluster/gls/mk_compile.py) ----\n"
if mode != "rtl":
    ud = "+define+ARM_UD_MODEL " if mode == "zd" else ""
    add += (
        f"if {{[catch {{ vlog -incr -work work {q([cells])} }}]}} {{return 1}}\n"
        # one vlog per macro: the ARM models `define ARM_UD_SEQ etc. in their own timescale (ps / ns),
        # in one compilation unit the first model's definition would leak into the next
        + "".join(f"if {{[catch {{ vlog -incr -work work {ud}{q([m])} }}]}} {{return 1}}\n" for m in macros)
        + f"if {{[catch {{ vlog -incr -work work -timescale 1ns/1ps {q([netlist])} }}]}} {{return 1}}\n"
    )
gls = "+define+GLS " if mode != "rtl" else ""
add += f"if {{[catch {{ vlog -incr -sv -work work -override_timescale 1ns/1ps {gls}{q([trace])} }}]}} {{return 1}}\n"

i = text.rstrip().rfind("return 0")
if i < 0:
    sys.exit("no final 'return 0' in " + src)
sys.stdout.write(text[:i] + add + text[i:])
