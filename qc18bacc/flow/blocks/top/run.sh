#!/usr/bin/env bash
# Chip top qb_chip (config: blocks/top/top.env + top.cfg; flow/README.md).  On the build host, in this order:
#   qc18bacc/flow/blocks/top/run.sh views      block views TOP_ABS from the block runs (top.env): LEFs, ETMs (OpenROAD
#                                              copies *_ins.lib / *_or.lib), PT dbs, measured insertion delays ins_tt.txt
#   qc18bacc/flow/blocks/top/run.sh fp <tag>   init, macro dump, floorplan/top_fp.py (<run>/mplace.tcl), floorplan + pdn,
#                                              power-grid check ($B/pnr/<tag>)
#   qc18bacc/flow/blocks/top/run.sh pnr <tag>  place .. GRT + post-GRT repair, db/grt.odb + route.guide (QC_PNR_FROM
#                                              [place] / QC_PNR_TO select a step range)
#   qc18bacc/flow/blocks/top/run.sh hold <tag> post-GRT hold + antenna repair in a fresh process (repair/top_hold.tcl;
#                                              knobs R43_HGRT0 R43_HPAR R43_HINC R43_HOLD pass through)
#   qc18bacc/flow/blocks/top/run.sh dr <tag>   detailed route + finish (route/dr.sh), SPEF tt + ss for PT
#   qc18bacc/flow/blocks/top/run.sh antenna <tag>  LEF-rule antenna check of db/route_dr (signoff/antenna.tcl)
#   qc18bacc/flow/blocks/top/run.sh pt <tag> [corners "tt ss"]  PrimeTime per corner (signoff/pt/top_chip.tcl) ->
#                                              $B/pnr/<tag>/pt_<period>_<c>/
#   qc18bacc/flow/blocks/top/run.sh lvs <tag> [rundir $B/drc/<tag>/lvs]  Calibre LVS with the hard blocks and SRAMs as
#                                              LVS BOX black boxes (pin-only stubs from their LEFs)
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/top.env"
step=${1:?step}; tag=${2:-}; d=$B/pnr/$tag; cfg=$here/top.cfg
echo "TOP_STEP $step $tag $(date +%T)"
# environment of every OpenROAD process that sources top.cfg (run_pnr.sh, route/dr.sh, common/or.sh); block insertion
# delays from the views (each block's own measured tt p50)
ins() { [ -s "$TOP_ABS/ins_tt.txt" ] && awk -v b=$1 '$1 == b {print $2}' "$TOP_ABS/ins_tt.txt"; }
export QC_PNR_THREADS=${QC_PNR_THREADS:-16} QB8_DR_THREADS=16 QB_TOP_ABS=$TOP_ABS QB_TOP_PERIOD=$TOP_PERIOD \
  QB11_INS=$(ins col) QB14_HINS=$(ins hub) QB14_AINS=$(ins act) QB15_GADJ_L=$TOP_GADJ_L \
  QB35_GRTHOLD=$TOP_GRTHOLD QB43_GRTANT=$TOP_GRTANT
pnr_env() {   # fp / pnr: netlist tag, macro PDN (floorplan/pdn_macro.tcl), post-CTS hook (the chip IO latency is 0 until
              # it is measured after CTS, repair/top_io_latency.tcl)
    export QB_SYN=$TOP_SYN QB_PDN_BLKX="qb_hub qb_act2_blk" \
      QB43_SRAM_CONN="{M3 M7}" QB43_RF_M4OFF=9.4 QB_PC_HOOK=$QBF/repair/post_cts_none.tcl
}
case $step in
views) A=$TOP_ABS; E=$QBF/signoff/etm; mkdir -p "$A"
     # act / hub: the block runs' ring LEFs with antenna data, ETMs, PT dbs; column: ring LEF of its antenna abstract
     ln -sf "$TOP_ACT/qb_act2_blk_ant_ring.lef" "$A/qb_act2_blk.lef"; ln -sf "$TOP_HUB/qb_hub_ant_ring.lef" "$A/qb_hub.lef"
     "$PY" -I "$E/lef_ring.py" "$TOP_COL_RUN/out/qb_col_blk_ant.lef" "$A/qb_col_blk.lef" 1.5 | head -3
     for c in tt ss ff; do
       for f in "$TOP_ACT/qb_act2_blk_$c.lib" "$TOP_ACT/qb_act2_blk_${c}_lib.db" "$TOP_HUB/qb_hub_$c.lib" "$TOP_HUB/qb_hub_${c}_lib.db" \
           "$TOP_COL_RUN/out/etm/qb_col_blk_${c}_lib.db"; do ln -sf "$f" "$A/"; done
       # column OpenROAD ETM: its own measured latency range of this corner as clock-tree-path arcs ("p50 min max")
       set -- $(cat "$TOP_COL_RUN/out/clk_lat_$c.txt")
       "$PY" -I "$E/etm_ins.py" "$TOP_COL_RUN/out/etm/qb_col_blk_$c.lib" "$A/qb_col_blk_${c}_ins.lib" "$3" "$2"
       # act OpenROAD ETM without output-pin checks (rsz repairEndHold crash on clk -> pin check endpoints, results/r46.md)
       "$PY" -I "$E/etm_nooutchk.py" "$TOP_ACT/qb_act2_blk_$c.lib" "$A/qb_act2_blk_${c}_or.lib" | tail -1
     done
     # block insertion delays (tt p50, ns) for the top clock tree / balancing / class reports
     for b in col:$TOP_COL_RUN hub:$TOP_HUB_RUN act:$TOP_ACT_RUN; do echo "${b%%:*} $(cut -d' ' -f1 "${b#*:}/out/clk_lat_tt.txt")"; done > "$A/ins_tt.txt"
     cat "$A/ins_tt.txt"; ls -la "$A" ;;
fp)  pnr_env
     QC_PNR_TO=init "$ROOT/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$QBF/floorplan/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     "$PY" -I "$QBF/floorplan/top_fp.py" "$d/macros.txt" "$TOP_ABS" "$d/mplace.tcl" $TOP_X0 $TOP_HUBX $TOP_NB || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$ROOT/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag"
     n=$(grep -c "check_power_grid true" "$d/summary.txt"); echo "TOP_PG check_power_grid true $n of 2"
     # PSM cannot see through block abstracts: islands that lie inside a hard block (on its PG pins, joined by the
     # block's own grid) are listed but tolerated; any unconnected node outside the hub bbox fails the step.
     nin=$(grep PSM-0038 "$d/openroad.log" | wc -l)
     nout=$(grep "PSM-0038.*location" "$d/openroad.log" | sed 's/.*location (\([0-9.]*\)um, \([0-9.]*\)um).*/\1 \2/' | awk -v B="$TOP_PGBB" 'BEGIN{split(B,b," ")} {if(!($1>=b[1]&&$1<=b[3]&&$2>=b[2]&&$2<=b[4])) n++} END{print n+0}')
     echo "TOP_PG unconnected nodes $nin, outside the hub bbox ($TOP_PGBB) $nout"
     [ "$n" = 2 ] || [ "$nout" = 0 ] || { echo "TOP_FAIL power grid check"; exit 1; } ;;
pnr) pnr_env
     QC_PNR_FROM=${QC_PNR_FROM:-place} "$ROOT/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag"
     case ${QC_PNR_TO:-finish} in route|finish) [ -f "$d/db/grt.odb" ] || { echo "TOP_FAIL no db/grt.odb"; exit 1; } ;; esac ;;
hold) "$QBF/common/or.sh" "$tag" "$QBF/repair/top_hold.tcl" r43_hold43.log
     grep -q "r43 hold43 done" "$d/r43_hold43.log" || { echo "TOP_FAIL hold"; exit 1; } ;;
dr)  rm -f "$d/db/init.odb" "$d/db/floorplan.odb"   # (disk: as the r43_a chains did)
     "$QBF/route/dr.sh" "$tag" || exit 1
     QC_SPEF_UNESC=1 "$QBF/signoff/spef.sh" "$tag" "tt ss" ;;
antenna) R29_DB=route_dr R29_TAG=dr "$QBF/common/or.sh" "$tag" "$QBF/signoff/antenna.tcl" r29_antd.log
     grep -hi "R29_ANTD\|found\|violat" "$d/r29_antd.log" | tail -4 ;;
pt)  qb_kit
     for c in ${3:-tt ss}; do o=$d/pt_${TOP_PERIOD}_$c; mkdir -p "$o"
     ( cd "$d" && . ./kit.env; set -a; . "$B/syn/$TOP_SYN/run.env"; set +a
       C=$(echo $c | tr a-z A-Z); v=QC_EXTRA_DB_$C; m=""
       for f in ${!v}; do case $f in *qb_col_blk*) ;; *) m="$m $f" ;; esac; done
       export QC_EXTRA_DB_$C="$m $TOP_ABS/qb_col_blk_${c}_lib.db $TOP_ABS/qb_hub_${c}_lib.db $TOP_ABS/qb_act2_blk_${c}_lib.db"
       export QC_SDC=$here/pt_sdc.tcl QC_PERIOD=$TOP_PERIOD QB35_TOPL=0
       QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c qb_pt "pt_chip_$c.log" pt_shell -f "$QBF/signoff/pt/top_chip.tcl"; r=$?
       cat "pt_chip_$c.txt"
       cp pt_chip_$c.txt pt_chip_$c.log rpt/r39_${c}_viol.txt rpt/pt_chip_${c}_*.rpt "$o/" 2>/dev/null; exit $r ) > "$o/run.log" 2>&1 &
     done; qb_wait; r=$?
     for c in ${3:-tt ss}; do o=$d/pt_${TOP_PERIOD}_$c; echo "PT_DONE $tag $TOP_PERIOD $c"
       grep -E "spef_nets|^all|^reg2reg|hold_reg2reg|violating|hub_ft|hub2act|act2col|io_|R39LAT|unconstrained" "$o/pt_chip_$c.txt"
       grep R43_AUTOL "$o/pt_chip_$c.log"; grep PT_ERRORS "$o/run.log"; done; [ $r = 0 ] || exit 1 ;;
lvs) r=${3:-$B/drc/$tag/lvs}; C=$QBF/signoff/calibre; mkdir -p "$r"; cd "$r" || exit 1
     . "$d/kit.env"; . "$C/kl.sh"
     # block LEFs (= MACRO_LEFS of the run: TOP_ABS) and SRAM LEFs; both become pin-only LVS BOX cells
     bl=""; ml=""; for f in $MACRO_LEFS; do case $(basename "$f") in qb_col_blk.lef|qb_hub.lef|qb_act2_blk.lef) bl="$bl $f" ;; *) ml="$ml $f" ;; esac; done
     echo "TOP_LVS lefs $MACRO_LEFS"
     "$PY" -I "$C/lefstub.py" "$r/stubs.spi" "$r/stubs.box" $MACRO_LEFS || exit 1
     # LEF abstracts -> GDS cells (signoff/calibre/kl.sh kl_abs): blocks without stack cuts (their PG pins cross on
     # adjacent layers), SRAMs with them (R38 F5: M1-M3 pins at one spot)
     kl_abs "$tag" 0 "$r/abs_blk.gds" $bl && kl_abs "$tag" 1 "$r/abs_mac.gds" $ml || { echo "TOP_FAIL LEF abstract GDS"; exit 1; }
     QB38_GDS_EXTRA="$r/abs_blk.gds $r/abs_mac.gds" bash "$C/gds.sh" "$tag" "$d/out/$TOP.def" "$r/top.gds" $MACRO_LEFS || exit 1
     bash "$C/lvs_src.sh" "$d/out/${TOP}_pg.v" "$r/top.spi" "$r/stubs.spi" || exit 1
     { echo '/^LVS ISOLATE SHORTS YES/a\'; echo 'LAYOUT CASE YES\'; echo 'SOURCE CASE YES\';
       sed '$!s/$/\\/' "$r/stubs.box"; } > "$r/deck.sed"
     QB36_LVS_SED="-f $r/deck.sed" bash "$C/cal.sh" lvs "$r/top.gds" "$TOP" "$r/top.spi" "$r/cal" 8 || exit 1 ;;
*) sed -n '2,20p' "$0"; exit 1 ;;
esac
echo "TOP_DONE $step $tag $(date +%T)"
