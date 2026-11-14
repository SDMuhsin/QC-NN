#!/usr/bin/env bash
# Post-route of a routed qb_col_blk run (results/r5a.md), on the build host from the repository root:
#   qc18bacc/impl/r5a/post.sh <tag> [steps]   steps (default "spef pt abs etm"):
#     spef  def2spef ss + ff (tt from the flow)       pt   PrimeTime sign-off tt / ss with the IO budget (pt_blk.tcl)
#     abs   abstract LEF (write_abstract_lef -bloat_factor 0: exact shapes, pnr_pe.md)   etm  ETMs tt / ss / ff
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
tag=$1; steps=${2:-spef pt abs etm}
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; dir=$QC_BUILD/pnr/$tag
. "$root/flow/tsmc65/common/tool.sh"
export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
. "$dir/kit.env"
for s in $steps; do case $s in
spef) QB_SPEF_CORNERS="ss ff" "$root/qc18bacc/impl/pnr/run.sh" spef "$tag" ;;
pt|etm)
    ( set -a; . "$(dirname "$NETLIST")/run.env"; set +a
      export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0}
      cd "$dir" || exit 1
      if [ $s = pt ]; then
          for c in ${QB_PT_CORNERS:-tt ss}; do
              QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c qc_tool "pt_blk_$c.log" pt_shell -f "$here/pt_blk.tcl"
              echo "PT_BLK $c errors $(grep -c '^Error' pt_blk_$c.log)"; cat "pt_blk_$c.txt"
          done
      else
          for c in tt ss ff; do
              QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c qc_tool "etm_$c.log" pt_shell -f "$here/etm.tcl"
              echo "ETM $c errors $(grep -c '^Error' etm_$c.log); $(ls out/etm/ 2>/dev/null | tr '\n' ' ')"
          done
      fi ) ;;
abs)
    cat > "$dir/abs.tcl" <<EOT
source \$::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $dir
source \$::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load finish
write_abstract_lef -bloat_factor 0 $dir/out/$TOP.lef
# abutment check: every act[b] / act_o[b] pair on the same layer and y, on the west / east die edge
set blk [ord::get_db_block]; set die [\$blk getDieArea]; set ok 0; set bad 0
foreach bt [\$blk getBTerms] {
    if {![regexp {^act\\[(\\d+)\\]\$} [\$bt getName] -> b]} { continue }
    set x [lindex [[lindex [\$bt getBPins] 0] getBoxes] 0]
    set y [lindex [[lindex [[\$blk findBTerm "act_o\\[\$b\\]"] getBPins] 0] getBoxes] 0]
    if {[\$x yMin] == [\$y yMin] && [\$x yMax] == [\$y yMax] && [[\$x getTechLayer] getName] eq [[\$y getTechLayer] getName]
        && [\$x xMin] == [\$die xMin] && [\$y xMax] == [\$die xMax]} { incr ok } else { incr bad }
}
puts "QB5_ABUT act pairs ok \$ok bad \$bad die [expr {[\$die dx] / 2000.0}] x [expr {[\$die dy] / 2000.0}] um"
if {[catch {check_antennas -report_file $dir/rpt/antenna.rpt} e]} { puts "QB5_ANT error \$e" } else { puts "QB5_ANT done" }
exit
EOT
    ( cd "$dir" && QC_FLOW=$FLOW QC_PNR_OUT=$dir QC_PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3 \
      ${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad -no_init -no_splash -exit -log abs.log abs.tcl > abs.out 2>&1 < /dev/null )
    grep -E "QB5_ANT|QB5_ABUT|ANT-|violat" "$dir/abs.log" | tail -5
    echo "ABS_DONE pins $(grep -c '^  PIN' $dir/out/$TOP.lef) $(grep -m1 -A0 'SIZE' $dir/out/$TOP.lef)" ;;
esac; done
echo R5A_POST_DONE $tag
