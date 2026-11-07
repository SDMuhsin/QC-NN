#!/usr/bin/env bash
# Host side of the ablation flow (run by qcacc/ablation/run.sh on the tau host, from R = the host work dir, e.g.
# /tmp/$USER/qcacc_abl, which holds flow/ (copy of the synthesis tree's flow/tsmc65 incl. site files), rtl/, vec/
# and abl/ (this directory)).  Every step writes small text summaries under R/out/ (fetched by run.sh).
#   [ABL_PERIOD_SYN=<ns> ABL_TAG_SFX=<sfx>] remote.sh syn <v>   (fmax runs at a tighter clock: tag abl_<v><sfx>)
#   remote.sh syn   <v>                DC 4.2 ns ss (WireAreaLowkCon via site.tcl) + PT ss / tt / ff   (v = dense|ternary|qc)
#   remote.sh sdf   <v>                DC tt SDF + ideal clock / reset view (flow/tsmc65/sim/sdf_idealclk.py)
#   remote.sh cells                    Questa library of the standard cells (once)
#   remote.sh gls   <point> <zd|sdf>   Questa GLS of a vector file (point = dense_s2|ternary|qc|dense_base), SAIF of the busy window
#   remote.sh glssum <point> <zd|sdf>   summary of a GLS run (out/gls_<point>_<mode>.txt)
#   remote.sh power <point> <zd|sdf>   PrimeTime PX at tt, 2.8 ns, from that SAIF
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
FLOW=$R/flow/tsmc65
P=${ABL_PERIOD_SYN:-4.2}; CLKPS=${ABL_CLK_PS:-2800}
QUESTA=${ABL_QUESTA:-/CMC/scripts/siemens.questasim.2022.1_2.csh}
export QC_BUILD=$R/build QC_SDC=$R/abl/constraints.sdc QC_CLK=clock QC_PT_HOOK=$R/abl/pt_hook.tcl QC_CORES=${QC_CORES:-4}
mkdir -p "$R/out"
variant() { case $1 in dense_s2|dense_base|dense) echo dense;; *) echo "$1";; esac; }
bw() { case $1 in dense) echo 512;; ternary) echo 128;; qc) echo 64;; esac; }
cmd=$1; shift
case $cmd in
syn)
  v=$1; top=AblGemm_$v; t=abl_$v${ABL_TAG_SFX:-}
  echo "$R/rtl/$top.sv" > "$R/rtl/$v.f"
  "$FLOW/syn/run_dc.sh" "$R/rtl/$v.f" "$top" "$P" "$t" > "$R/out/syn_$v.log" 2>&1
  "$FLOW/sta/run_pt.sh" "$t" ss tt ff >> "$R/out/syn_$v.log" 2>&1
  S=$QC_BUILD/syn/$t
  mkdir -p "$R/out/$t"; cp "$S/summary.txt" "$S"/pt_*.txt "$S/run.env" "$R/out/$t/"
  # hierarchy-only area (no cell names): report_area -hierarchy rows
  awk '/^-----/{n++; next} n>=1 && NF>=6 && $1 !~ /^Total/' "$S/rpt/area.rpt" > "$R/out/$t/area_hier.txt"
  grep -E "Number of|Total cell area|Combinational area|Noncombinational area|Buf/Inv" "$S/rpt/area.rpt" | head -12 >> "$R/out/$t/area_hier.txt"
  grep -E "clock gat|Number of Gated|Ungated|Total Number" "$S/rpt/clock_gating.rpt" | head -8 > "$R/out/$t/clock_gating.txt"
  echo "ABL_SYN_DONE $t"; cat "$S/summary.txt"; grep -h -E "setup_wns|reg2reg" "$S"/pt_*.txt ;;
sdf)
  v=$1; top=AblGemm_$v; S=$QC_BUILD/syn/abl_$v; D=$R/sdf; mkdir -p "$D"; cd "$D"
  tcsh -f -c "source $FLOW/site/site.csh; setenv QC_FLOW $FLOW; setenv SYN $S; setenv TOP $top; setenv SDF $D/${top}_tt.sdf; dc_shell -f $R/abl/write_sdf.tcl" > "write_sdf_$v.log" 2>&1
  grep -q QC_SDF_DONE "write_sdf_$v.log" || { tail "write_sdf_$v.log"; exit 1; }
  # TB inputs change at 20 % of the period (= SDC input delay) -> no extra port delay (0)
  python3 "$FLOW/sim/sdf_idealclk.py" --clock-celltype CKLNQD "${top}_tt.sdf" 0 clock reset | gzip -1 > "${top}_tt_idealclk.sdf.gz"
  grep slack "tt_timing_$top.rpt" | head -2 > "$R/out/sdf_$v.txt"; ls -la "${top}_tt_idealclk.sdf.gz" | awk '{print $5}' >> "$R/out/sdf_$v.txt"
  echo "ABL_SDF_DONE $v"; cat "$R/out/sdf_$v.txt" ;;
cells)
  C=$(tcsh -f -c "source $FLOW/site/site.csh; echo \$QC_CELL_V")
  mkdir -p "$R/gls"; cd "$R/gls"
  tcsh -f -c "source $QUESTA >& /dev/null; rm -rf cells; vlib cells; vlog -work cells $C" > cells.log 2>&1
  tail -2 cells.log ;;
gls)
  pt=$1; m=$2; v=$(variant "$pt"); top=AblGemm_$v; W=$R/gls/${pt}_$m; rm -rf "$W"; mkdir -p "$W"; cd "$W"
  if [ "$m" = zd ]; then VO="+acc=n +nospecify +notimingchecks"; SD=""; else VO="+acc=n"; SD="-sdftyp /tb_abl/dut=$R/sdf/${top}_tt_idealclk.sdf.gz -suppress 16107"; fi
  tcsh -f -c "source $QUESTA >& /dev/null; vlib work; vlog -work work $QC_BUILD/syn/abl_$v/$top.v; \
    vlog -sv -work work +define+DUT=$top +define+BW=$(bw "$v") $R/abl/tb_abl.sv; \
    vsim -c -L $R/gls/cells -t 1ps -voptargs=\"+acc=npr+tb_abl $VO\" $SD -suppress 3009 tb_abl +VEC=$R/vec/$pt.txt +PERIOD_PS=$CLKPS -do $R/abl/abl.do" > run.log 2>&1
  "$0" glssum "$pt" "$m" > /dev/null
  echo "ABL_GLS_DONE $pt $m"; cat "$R/out/gls_${pt}_$m.txt" ;;
glssum)
  pt=$1; m=$2; W=$R/gls/${pt}_$m; o=$R/out/gls_${pt}_$m.txt
  { grep -E "ABL_(INFO|SAIF|RESULT|MISMATCH)" "$W/run.log" | head -8
    grep -E "SDF Backannotation|^# Errors:" "$W/run.log" | tail -2
    echo "timing_check_violations $(grep -cE '\$(setup|hold|setuphold|recovery|removal|width)\(' "$W/run.log")"
    echo "fatal_or_error_lines $(grep -cE '^# \*\* (Error|Fatal)' "$W/run.log")"
    ls -la "$W/abl.saif" 2>/dev/null | awk '{print "saif_bytes", $5}'; } > "$o"
  cat "$o" ;;
power)
  pt=$1; m=$2; v=$(variant "$pt"); top=AblGemm_$v; W=$R/gls/${pt}_$m; cd "$W"
  pns=$(awk "BEGIN{print $CLKPS/1000}")
  for z in 0 1; do o=pt; x=""; [ $z = 1 ] && o=ptz && x=_zwlm      # pt: synthesis WLM, ptz: zero wire load (M3-comparable)
    tcsh -f -c "source $FLOW/site/site.csh; setenv QC_FLOW $FLOW; setenv SYN $QC_BUILD/syn/abl_$v; setenv TOP $top; \
      setenv ABL_PT_ZWLM $z; setenv QC_SDC $QC_SDC; setenv QC_PERIOD $pns; setenv SAIF $W/abl.saif; setenv OUT $W/$o; \
      pt_shell -f $R/abl/pt_power.tcl" > $o.log 2>&1
    cp $o.txt "$R/out/power_${pt}_$m${x}.txt"; cp ${o}_cells.txt "$R/out/power_${pt}_$m${x}_cells.txt"
  done
  echo "ABL_POWER_DONE $pt $m errors $(cat pt.log ptz.log | grep -c '^Error')"; grep -h "Total Power" pt.txt ptz.txt ;;
*) sed -n 2,12p "$0"; exit 1 ;;
esac
