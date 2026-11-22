#!/usr/bin/env bash
# Netlists and other inputs of the P&R flows (DC topographical tt, flow/tsmc65 run_dc.sh / run_pt.sh).  On the build host:
#   qc18bacc/flow/synth/run.sh col               column block DC -> syn/qb_col_blk_r5d_s20_tt_p1.65_topo (+ PT tt ss; results/r5d.md)
#   qc18bacc/flow/synth/run.sh act [tag]         act block DC (S1T) -> syn/<tag [r35_act]> + PT tt ss with act_pt_classes.tcl (results/r20.md)
#   qc18bacc/flow/synth/run.sh chip <tag>        chip DC (QB_TOP_PTR=1 RTL, 8 column ETMs from $B/r5b_blk, ARM macros) -> syn/<tag>
#                                                (r26_ptr for the hub partition, r35_ptr for the top; results/r26.md, r35.md)
#   qc18bacc/flow/synth/run.sh part <syn tag> <dir>   hub partition (synth/partition.sh) -> $B/<dir> (r26_w for the hub, r35_w for the top)
#   qc18bacc/flow/synth/run.sh topnl <part dir>  top netlist -> $B/r35/top_r35.v (+ _bpins / _equiv / _actmap; top_nl.py)
#   qc18bacc/flow/synth/run.sh actpins           column act-pin table of the reference abstract -> $B/r35/col_act_pins.txt (act P&R pins)
#   qc18bacc/flow/synth/run.sh macros            ARM SRAM views (flow/tsmc65/sram/mc_gen.sh) of macros.txt + macros_fc.txt
# The commands are those recorded for the current inputs (results/*.md, tau logs); see flow/README.md for what was not recorded.
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../common/env.sh"
COMPILE="compile_ultra -no_autoungroup -gate_clock -spg"
R10W='+define+QB_HPW=144+QB_TOP_RSH=2+QB_HEAD_PCOL=1+QB_HEAD_IREG=2+QB_TOP_WBQ=2+QB_ACT_CTXR+QB_ACT_LDR+QB_ACT_CNT+QB_ACT_SRA+QB_SEQ_LPS+QB_SEQ_CMH+QB_SEQ_TKS+QB_PRM_BAR+QB_SEQ_DSP+QB_SEQ_TGO+QB_PRM_NUR+QB_SEQ_NXW+QB_SEQ_RAL+QB_ACT_S1M=1+QB_TOP_FPR=1+QB_TOP_WBK=1+QB_TOP_FFT=1+QB_SEQ_DEP+QB_ACT_S2M+QB_PRM_COL=1+QB_WB_COL=1'
step=${1:?step}
case $step in
col) QC_TOPO=1 QC_HOOK=$here/col_dc_hook.tcl QC_COMPILE="$COMPILE" QB_FL=$here/col_blk.f \
       "$here/dc.sh" all qb_col_blk 1.65 qb_col_blk_r5d_s20_tt_p1.65_topo ;;
act) s=${2:-r35_act}
     QC_TOPO=1 QC_HOOK=$here/act_dc_hook.tcl QC_COMPILE="$COMPILE" QB_FL=$here/act_blk.f "$here/dc.sh" syn qb_act2_blk 1.65 $s &&
     QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK=$here/act_pt_classes.tcl QC_CLK=clk QC_CORES=8 "$ROOT/flow/tsmc65/sta/run_pt.sh" $s tt ss
     grep "QB13_RPL\|QB20_RPL" "$B/syn/$s/dc.log"; grep -c VIOLATED "$B/syn/$s/rpt/violators.rpt"; grep -A3 "Nets With Violations" "$B/syn/$s/rpt/qor.rpt" ;;
chip) t=${2:?tag}; G=$B/${t}_gen; "$here/chip_gen.sh" "$G"
     echo "$R10W+QB_TOP_PTR=1" >> "$G/qb_chip_r5b.f"
     QB_FL=$G/qb_chip_r5b.f QB_MACROS_EXTRA=$here/macros_fc.txt \
     QB_EXTRA_DB_TT=$B/r5b_blk/qb_col_blk_tt_lib.db QB_EXTRA_DB_SS=$B/r5b_blk/qb_col_blk_ss_lib.db \
     QB_EXTRA_DB_FF=$B/r5b_blk/qb_col_blk_ff_lib.db "$here/chip_dc.sh" syn qb_chip 1.65 "$t" ;;
part) "$here/partition.sh" "${2:?syn tag}" "$B/${3:?work dir}" ;;
topnl) mkdir -p "$B/r35"; cd "$B/r35" && "$PY" -I "$here/top_nl.py" "$B/${2:?part dir}/qb_chip_r9b_c.v" top_r35 | tail -20 ;;
actpins) mkdir -p "$B/r35"; python3 -I "$here/col_act_pins.py" "$B/r5b_blk/qb_col_blk_ring.lef" "$B/r35/col_act_pins.txt" ;;
macros) "$ROOT/flow/tsmc65/sram/mc_gen.sh" gen "$here/macros.txt"; "$ROOT/flow/tsmc65/sram/mc_gen.sh" gen "$here/macros_fc.txt" ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
echo "SYNTH_DONE $step $(date +%T)"
