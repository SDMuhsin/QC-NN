#!/usr/bin/env bash
# Host side of the QC18-ACC array ablation (run by qc18acc/ablation/run.sh over ssh, from the host-local clone
# /tmp/$USER/qc18acc/repo).  Work dir AB = /tmp/$USER/qc18acc/abl (builds, vectors, GLS, SAIF stay there; only
# the summaries of AB/out, which name design objects only, are fetched).
#   remote.sh syn   <v>              DC 3.3 ns ss (impl/constraints.sdc, WLM WireAreaLowkCon enclosed) + PT ss/tt/ff
#   remote.sh sdf   <v>              DC tt SDF (synthesis WLM) + ideal clock / reset, 0.5 ns input delay view
#   remote.sh gls   <v> <point...>   VCS tt-SDF GLS at 2.5 ns (timing checks on), SAIF of the PE busy window
#   remote.sh glsrun <v> <point>    one point on the compiled simv of 'gls' (own copy: points can run in parallel)
#   remote.sh glssum <v> <point>    summary of a GLS point (out/gls_<point>.txt)
#   remote.sh power <v> <point...>   PrimeTime PX tt 1.0 V, 2.5 ns, synthesis WLM, from that SAIF
# v = qc | tern | int8 (top qab_top_<v>, tag qab_<v>_w3.3); point = <vector name>, e.g. qc_L2, int8c_L4.
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
SELF=$REPO/qc18acc/ablation/remote.sh
FLOW=$REPO/flow/tsmc65
AB=${QAB_DIR:-/tmp/$USER/qc18acc/abl}
export QC_BUILD=$AB/build QC_SDC=$REPO/qc18acc/impl/constraints.sdc QC_PT_HOOK=$REPO/qc18acc/impl/pt_hook.tcl
export QC_CLK=clk QC_CORES=${QC_CORES:-8}
P=${QAB_PERIOD:-3.3}; CLKPS=2500
# QAB_ZD=1: zero-delay GLS (no SDF, +nospecify +notimingcheck) for gls / glsrun / glssum / power: work dir gls_zd/,
# summaries gls_zd_<point>.txt, power_zd_<point>*.txt (glitch-free reference)
ZD=${QAB_ZD:-0}; X=""; [ "$ZD" = 1 ] && X=_zd
mkdir -p "$AB/out"
defs() { case $1 in qc) echo "+define+TOP=qab_top_qc+WB=10+ACC=20";; tern) echo "+define+TOP=qab_top_tern+WB=128+ACC=21";;
         int8) echo "+define+TOP=qab_top_int8+WB=512+ACC=32";; esac; }
tcs() { tcsh -f -c "source $FLOW/site/site.csh; $*"; }
cmd=$1; v=$2; shift 2
top=qab_top_$v; t=qab_${v}_w$P; S=$QC_BUILD/syn/$t; O=$AB/out
case $cmd in
syn)
  "$FLOW/syn/run_dc.sh" "$REPO/qc18acc/ablation/rtl/qab.f" "$top" "$P" "$t" > "$O/syn_$v.log" 2>&1
  "$FLOW/sta/run_pt.sh" "$t" ss tt ff >> "$O/syn_$v.log" 2>&1
  mkdir -p "$O/$t"; cp "$S/summary.txt" "$S"/pt_ss.txt "$S"/pt_tt.txt "$S"/pt_ff.txt "$O/$t/"
  # hierarchy area rows (instance, totals, design name), no library cells
  awk '/^-----/{n++; next} n>=1 && NF>=7 && $1 !~ /^Total/' "$S/rpt/area.rpt" > "$O/$t/area_hier.txt"
  grep -E "Number of|Total cell area|Combinational area|Noncombinational area|Buf/Inv" "$S/rpt/area.rpt" | head -12 > "$O/$t/area_sum.txt"
  echo "QAB_SYN_DONE $t"; cat "$S/summary.txt"; grep -h "fmax" "$S"/pt_*.txt ;;
sdf)
  D=$AB/sdf/$v; mkdir -p "$D"; cd "$D"
  tcs "setenv QC_FLOW $FLOW; setenv SYN $S; setenv TOP $top; setenv SDF $D/${top}_tt.sdf; setenv QC_SDC $QC_SDC; setenv QC_PERIOD $P; dc_shell -f $REPO/qc18acc/ablation/write_sdf.tcl" > write_sdf.log 2>&1
  grep -q QC_SDF_DONE write_sdf.log || { tail write_sdf.log; exit 1; }
  python3 "$FLOW/sim/sdf_idealclk.py" --clock-celltype CKLNQD "${top}_tt.sdf" 0.5 clk rst_n > "${top}_idealclk.sdf" 2> idealclk.log
  { grep -m2 slack tt_timing.rpt; cat idealclk.log; } > "$O/sdf_$v.txt"; echo "QAB_SDF_DONE $v"; cat "$O/sdf_$v.txt" ;;
gls)
  W=$AB/gls$X/$v; mkdir -p "$W"; cd "$W"; rm -rf simv simv.daidir csrc
  SDFO="-sdf typ:tb_qab.dut:$AB/sdf/$v/${top}_idealclk.sdf +no_notifier"; [ "$ZD" = 1 ] && SDFO="+nospecify +notimingcheck"
  tcs "vcs -full64 -sverilog -timescale=1ns/1ps $S/$top.v $REPO/qc18acc/ablation/tb_qab.sv -top tb_qab -o simv \
    -v \$QC_CELL_V +define+QC_GLS $(defs "$v")+QAB_SAIF $SDFO" > vcs.log 2>&1
  [ -x simv ] || { grep -E "Error" -A3 vcs.log | head; exit 1; }
  for pt in "$@"; do "$SELF" glsrun "$v" "$pt"; done ;;
glsrun)
  pt=$1; W=$AB/gls$X/$v; D=$W/run_$pt; rm -rf "$D"; mkdir -p "$D"; cp -r "$W/simv" "$W/simv.daidir" "$D/"; cd "$D"
  tcs "./simv +VEC=$AB/vec/$pt.txt +PERIOD_PS=$CLKPS +SAIF=$W/$pt.saif" > "$W/$pt.log" 2>&1
  "$SELF" glssum "$v" "$pt" ;;
glssum)
  pt=$1; W=$AB/gls$X/$v
  { grep -E "QAB_(INFO|SAIF|RESULT|MISMATCH)" "$W/$pt.log" | head -6
    echo "sdf_annotation $(grep -ciE 'sdf.*(annotat|back)' "$W/vcs.log") timing_violations $(grep -c 'Timing violation' "$W/$pt.log")"
    echo "error_lines $(grep -cE '^Error|Fatal' "$W/$pt.log") saif_bytes $(stat -c %s "$W/$pt.saif" 2>/dev/null)"; } > "$O/gls${X}_$pt.txt"
  echo "QAB_GLS_DONE $pt"; cat "$O/gls${X}_$pt.txt" ;;
power)
  W=$AB/gls$X/$v
  for pt in "$@"; do
    D=$W/power_$pt; mkdir -p "$D"; cd "$D"
    tcs "setenv QC_FLOW $FLOW; setenv SYN $S; setenv TOP $top; setenv QC_SDC $QC_SDC; setenv QC_PERIOD $(awk "BEGIN{print $CLKPS/1000}"); \
      setenv SAIF $W/$pt.saif; setenv OUT $D/pt; pt_shell -f $REPO/qc18acc/ablation/pt_power.tcl" > pt.log 2>&1
    cp pt.txt "$O/power${X}_$pt.txt"; cp pt_cells.txt "$O/power${X}_${pt}_cells.txt"
    echo "QAB_POWER_DONE $pt errors $(grep -c '^Error' pt.log)"; grep "Total Power" pt.txt
  done ;;
*) sed -n 2,12p "$0"; exit 1 ;;
esac
