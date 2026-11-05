#!/usr/bin/env bash
# Gate-level simulation of the DC netlist of the KUL cluster inside the full chimera SoC
# (Questa 2022.1, remote host, default tau1). Same TB, host ELF and self-check as
# sim/chimera_vsim.sh; only the cluster RTL pickle is replaced by netlist + cells + macro models.
#   hw/kulcluster/gls/gls.sh compile|start|wait|summary   [zd|sdf]   (default mode zd)
#     zd   zero delay: +nospecify +notimingchecks, ARM macro models in unit-delay mode
#     sdf  DC write_sdf delays at tt (`sdf` step) in the STA-consistent view of sdf_idealclk.py
#          (ideal clock and reset networks, SDC input delay on the chimera-driven ports),
#          full ARM macro timing models, timing checks on; cluster clock KUL_GLS_CLK_SDF (3500 ps)
#   hw/kulcluster/gls/gls.sh sdf        DC: write the tt SDF of the netlist (remote, detached, ~3 min;
#                                       call again until it lists the .sdf.gz)
#   hw/kulcluster/gls/gls.sh undriven   static check: vopt-2958 undriven nets only feed unloaded port bits
# start runs vsim detached on the host (log $R/<mode>/run.log); wait polls it (<= 3 min per call,
# repeat until it prints GLS_DONE); summary copies the log and writes results/gls_<mode>.log.
# Prereqs: sim/chimera_vsim.sh compile (remote chimera tree + bender compile script),
#          sw/chimera_gemmx/build.sh (host ELF), the DC netlist and macro views on the host.
set -euo pipefail
KUL_NO_VLT=1 source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
STEP=${1:?step}; MODE=${2:-zd}
HOST=${KUL_VSIM_HOST:-tau1}
R=${KUL_GLS_DIR:-/tmp/ckp908/qcnn_kulgls}
SYN=${KUL_GLS_SYN:-/tmp/ckp908/qcnn_kulsyn/build/syn/kul_p3.5}
NET=$SYN/KULCluster_snax_KUL_cluster_wrapper.v
SYNTREE=${KUL_GLS_FLOW:-/tmp/ckp908/qcnn_kulsyn/tree/flow/tsmc65}   # flow of the synthesis run (site.csh, lib.tcl)
MAC=${KUL_GLS_MACROS:-/tmp/ckp908/qcnn_kulsyn/macros}
CELLS=${KUL_GLS_CELLS:-/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/verilog/tcbn65gplus_140b/tcbn65gplus.v}
SDF=$R/sdfgen/KULCluster_snax_KUL_cluster_wrapper_tt.sdf
SDFI=$R/sdfgen/KULCluster_snax_KUL_cluster_wrapper_tt_idealclk.sdf.gz    # what the sdf run annotates
CLK_SDF=${KUL_GLS_CLK_SDF:-3500}    # in ps (vsim -G of a time parameter takes simulator units); tt fmax of the pre-CTS netlist is ~433 MHz (impl/kulcluster)
QUESTA=${KUL_QUESTA:-/CMC/scripts/siemens.questasim.2022.1_2.csh}
ELF=${ELF:-$KUL_BUILD/sw/chimera_gemmx.memisl.elf}
G=$KUL_DIR/gls
W=$R/$MODE
rq() { ssh "$HOST" "tcsh -c 'source $QUESTA >& /dev/null; cd $W; $*'"; }
MACROS=$(printf "$MAC/%s/%s.v," kul_rf_512x64m4 kul_rf_512x64m4 kul_rf_128x128m1 kul_rf_128x128m1 kul_rf_128x40m1 kul_rf_128x40m1)

case $STEP in
compile)
  ssh $HOST "mkdir -p $W"
  python3 $G/mk_compile.py $KUL_BUILD/compile.chimera_kul.tcl $NET $CELLS ${MACROS%,} $W/gls_xcheck.sv \
    $([ $MODE = zd ] && echo --ud) > $KUL_BUILD/compile.gls_$MODE.tcl
  rsync -a $KUL_BUILD/compile.gls_$MODE.tcl $G/gls_xcheck.sv $HOST:$W/
  rq "rm -rf work; vlib work >& /dev/null; vsim -c -do \"source compile.gls_$MODE.tcl; quit\" >& compile.log; grep -c Error: compile.log; tail -3 compile.log"
  ;;
sdf)
  # detached; call again to see the status (QC_SDF_DONE in write_sdf.log when finished)
  if ssh $HOST "grep -q QC_SDF_DONE $R/sdfgen/write_sdf.log 2>/dev/null"; then
    rsync -a $G/sdf_idealclk.py $HOST:$R/sdfgen/
    # input delay of the chimera-driven ports = the SDC's set_input_delay (one value, min = max)
    IND=$(ssh $HOST "grep -o 'set_input_delay -clock [^ ]* *[0-9.]*' $R/sdfgen/tt.sdc | awk '{print \$NF}' | sort -u")
    [ "$(echo "$IND" | wc -l)" = 1 ] || { echo "expected one set_input_delay value, got: $IND"; exit 1; }
    ssh $HOST "cd $R/sdfgen; [ -s $SDFI ] || python3 sdf_idealclk.py $SDF $IND clk_i rst_ni | gzip -1 > $SDFI
      grep -E 'slack' tt_timing.rpt; ls -la $SDF $SDFI"; exit 0
  fi
  if ssh $HOST "pgrep -u \$USER -f '[d]c_shell.*write_sdf' >/dev/null"; then
    ssh $HOST "tail -2 $R/sdfgen/write_sdf.log"; echo SDF_RUNNING; exit 0
  fi
  ssh $HOST "mkdir -p $R/sdfgen"
  rsync -a $G/write_sdf.tcl $HOST:$R/sdfgen/
  DBTT=$(ssh $HOST ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
  ssh $HOST "cd $R/sdfgen && tcsh -f -c 'source $SYNTREE/site/site.csh; setenv QC_FLOW $SYNTREE; setenv SYN $SYN; setenv SDF $SDF; setenv QC_EXTRA_DB_TT \"$DBTT\"; (nohup dc_shell -f write_sdf.tcl >& write_sdf.log &)'"
  echo SDF_STARTED
  ;;
start)
  rsync -a $ELF $G/run_gls.tcl $G/gls_probe.tcl $HOST:$W/
  B=$W/$(basename $ELF)
  ACC='+acc=n+KULCluster_BlockGemm+KULCluster_PipelinedRescaleSIMD+KULCluster_snax_streamer_gemmX_Streamer +acc=rn+gls_xcheck'
  if [ $MODE = zd ]; then
    VOPT="+nospecify +notimingchecks $ACC"; SDFOPT=""
  else
    # SDF scope = the netlist top inside chimera (GLS_INFO cluster line of the zd run)
    VOPT="$ACC"; SDFOPT="-sdftyp /tb_chimera_soc/fix/dut/i_cluster_domain/i_chimera_cluster_kulcluster/i_test_cluster=$SDFI -G/tb_chimera_soc/fix/vip/ClkPeriodClu=$CLK_SDF -suppress 16107"
    # 16107: INTERCONNECT entries Questa cannot map (port nets split by the netlist's assigns);
    # all INTERCONNECT delays of this wire-load SDF are 0 (net delay is in the cell delays)
  fi
  rq "rm -f run.log; $([ -n "${GLS_STOP:-}" ] && echo "setenv GLS_STOP $GLS_STOP;") (nohup vsim -c tb_chimera_soc gls_bind -t 1ps -voptargs=\\\"$VOPT\\\" $SDFOPT -suppress 3009 -suppress 8386 -error 7 ${KUL_GLS_SIMARGS:-} +BOOTMODE=0 +PRELMODE=0 +BINARY=$B -do run_gls.tcl >& run.log &) ; sleep 2; head -3 run.log"
  ;;
wait)
  for i in $(seq 16); do   # <= ~3 min per call
    if ssh $HOST "grep -q 'Elapsed time\|Fatal' $W/run.log 2>/dev/null"; then break; fi
    sleep 10
  done
  ssh $HOST "grep -vE 'TFMPC|vopt-2958' $W/run.log | grep -E 'GEMMX_PROBE|GLS_|JTAG\] (SUCCESS|FAIL|Resumed)|Errors:|Fatal|Error:|exit code|Elapsed' | head -40; tail -1 $W/run.log; ps -o rss=,etime= -C vsimk 2>/dev/null | head -2"
  ssh $HOST "grep -q 'Elapsed time\|Fatal' $W/run.log" && echo GLS_DONE || echo GLS_RUNNING
  ;;
summary)
  mkdir -p $KUL_BUILD/gls_$MODE
  rsync -a $HOST:$W/run.log $HOST:$W/compile.log $KUL_BUILD/gls_$MODE/
  python3 $G/gls_summary.py --mode $MODE --run-log $KUL_BUILD/gls_$MODE/run.log \
    --rtl $KUL_DIR/results/gemmx_cycles.txt > $KUL_DIR/results/gls_$MODE.log
  cat $KUL_DIR/results/gls_$MODE.log
  ;;
undriven)
  ssh $HOST "python3 - $NET $R/zd/run.log" < $G/undriven_check.py
  ;;
*) sed -n '2,16p' "$0"; exit 1 ;;
esac
