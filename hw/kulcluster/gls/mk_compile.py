#!/usr/bin/env python3
"""Turn the bender-generated chimera RTL compile script (sim/chimera_vsim.sh compile) into the
gate-level one: the `vlog` block of the KUL cluster RTL pickle (kulcluster_sim.sv) is replaced by
the TSMC65 cell models, the ARM RF macro models and the DC netlist (same top module name
KULCluster_snax_KUL_cluster_wrapper, same port widths, so chimera_cluster_kulcluster binds it
unchanged). Every other block (chimera / cheshire / CVA6 / TB) is kept as is.

  mk_compile.py <rtl_compile.tcl> <netlist.v> <cells.v> <macro.v>[,<macro.v>...] <xcheck.sv> [--ud] > out.tcl
  --ud  compile the macro models in ARM unit-delay mode (zero-delay GLS); default: timing model (SDF)
"""
import re
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
ud = "--ud" in sys.argv
if len(args) != 5:
    sys.exit(__doc__)
rtl, netlist, cells, macros, xchk = args[0], args[1], args[2], args[3].split(","), args[4]

text = open(rtl).read()
blocks = re.split(r"(?=^if \{\[catch \{ vlog)", text, flags=re.M)
kul = [i for i, b in enumerate(blocks) if "kulcluster_sim.sv" in b]
if len(kul) != 1:
    sys.exit(f"expected one kulcluster_sim.sv block, found {len(kul)}")

mdef = "+define+ARM_UD_MODEL " if ud else ""
gls = (
    "# ---- gate-level KUL cluster (hw/kulcluster/gls/mk_compile.py) ----\n"
    f"if {{[catch {{ vlog -incr -work work \"{cells}\" }}]}} {{return 1}}\n"
    f"if {{[catch {{ vlog -incr -work work {mdef}{' '.join(chr(34) + m + chr(34) for m in macros)} }}]}} {{return 1}}\n"
    f"if {{[catch {{ vlog -incr -work work \"{netlist}\" }}]}} {{return 1}}\n"
    f"if {{[catch {{ vlog -incr -work work -sv \"{xchk}\" }}]}} {{return 1}}\n\n"
)
blocks[kul[0]] = gls
sys.stdout.write("".join(blocks))
