#!/usr/bin/env bash
# VCS simulation:   flow/tsmc65/sim/run_vcs.sh <tag> <tb_top> <filelist.f> [more.f ...]
# The file lists are flattened by common/flist.tcl (same rules as synthesis) and compiled as SystemVerilog.
# Environment (optional):
#   QC_GLS=1        gate-level: add the site cell models (QC_CELL_V of site.csh), zero-delay (+nospecify +notimingcheck)
#   QC_VCS_OPTS     extra vcs options      QC_SIM_OPTS  extra simv options (plusargs)
#   QC_PASS_RE      regex a passing simulation log must contain (PASS);  QC_FAIL_RE  must not contain (FAIL|Error|Fatal)
# Output: $QC_BUILD/sim/<tag>/: vcs.log, sim.log, flat.f; last line SIM_DONE <tag> PASS|FAIL.
set -u
. "$(dirname "$0")/../common/tool.sh"
[ $# -ge 3 ] || { sed -n '2,10p' "$0"; exit 1; }
tag=$1; tb=$2; shift 2
out=$BUILD/sim/$tag
rm -rf "$out"; mkdir -p "$out"
tclsh "$FLOW/common/flist.tcl" "$@" > "$out/flat.f" || exit 1
cd "$out" || exit 1
opts="-full64 -sverilog -timescale=1ns/1ps -f flat.f -top $tb -o simv ${QC_VCS_OPTS:-}"
[ "${QC_GLS:-0}" = 1 ] && opts="$opts -v \$QC_CELL_V +nospecify +notimingcheck +define+QC_GLS"
qc_tool vcs.log vcs $opts
crc=$?
src=1
if [ $crc = 0 ] && [ -x simv ]; then qc_tool sim.log ./simv ${QC_SIM_OPTS:-}; src=$?; fi
res=FAIL
[ $src = 0 ] && grep -qE "${QC_PASS_RE:-PASS}" sim.log && ! grep -qE "${QC_FAIL_RE:-FAIL|Error|Fatal}" sim.log && res=PASS
echo "SIM_DONE $tag $res vcs_rc $crc simv_rc $src $(qc_time vcs.log | sed 's/^/compile_/')"
grep -E "${QC_PASS_RE:-PASS}|${QC_FAIL_RE:-FAIL|Error|Fatal}" sim.log 2>/dev/null | head -5 | sed 's/^/  /'
