#!/usr/bin/env bash
# Gate-level simulation of the DC netlist of the Snitch cluster (impl/snitch_cluster, fp_p5.0_wlm) in
# the sim/ testbench (Questa 2022.1 on $GLS_HOST). Same TB, kernel ELFs and self-checking
# verifiers as sim/run_kernel.sh <kernel> vsim; only the RTL snitch_cluster_wrapper is replaced.
#   gls.sh setup                    netlist + macro models usask -> $GLS_HOST, RTL TB build there
#   gls.sh compile <mode>           compile + vopt (mode rtl | zd | sdf)
#   gls.sh start   <kernel> <mode>  verifier + simulation, detached on the host
#   gls.sh wait    <kernel> <mode>  poll (<= 9 min per call), prints GLS_DONE when finished
#   gls.sh summary <kernel> <mode>  logs back, verdict + cycles vs RTL -> build/gls/<kernel>_<mode>.txt
#   gls.sh report                   all summaries -> impl/snitch_cluster/gls/results.txt
#   gls.sh sdf                      DC write_sdf at tt on $GLS_SYNHOST, STA-consistent view (sdf_idealclk.py:
#                                   ideal clock + reset networks, SDC input delay on the TB-driven ports) -> $GLS_HOST
# modes: rtl = RTL + gls_trace.sv (validates the retire monitor against the upstream tracer)
#        zd  = netlist, +nospecify +notimingchecks, ARM macro models in unit-delay mode
#        sdf = netlist + DC tt SDF (ideal clock + reset, SDC input delay), ARM timing models, timing checks reported
#              (+no_notifier, see README), clock GLS_TCK_PS (default 4000)
# kernel: gemm_fp64 | conv2d (ELF from sim/run_kernel.sh <kernel> vsim, build/sim/runs/...)
set -euo pipefail
G=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$G/../../../sim/env.sh"
STEP=${1:?step}
H=${GLS_HOST:-tau5}
R=${GLS_DIR:-/tmp/ckp908/qcnn_snitchgls}      # host-local work area
SYNHOST=${GLS_SYNHOST:-usask}; SYN=${GLS_SYN:-/tmp/ckp908/qcnn/build/syn/fp_p5.0_wlm}
SYNMAC=${GLS_SYNMACROS:-/tmp/ckp908/qcnn/macros}
CELLS=${GLS_CELLS:-/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/verilog/tcbn65gplus_140b/tcbn65gplus.v}
QUESTA=${GLS_QUESTA:-/CMC/scripts/siemens.questasim.2022.1_2.csh}
TCK_SDF=${GLS_TCK_PS:-4000}
MACROS="qc_sp_1024x64m8 qc_rf_16x128m1"; MACV=$(for m in $MACROS; do printf "%s/%s.v " $m $m; done)
export REMOTE_HOST=$H REMOTE_WORK=$R/sim        # sim/ scripts run against this host / area
RWS=$REMOTE_WORK/ws/$SIM_CFG; RTGT=$RWS/target/snitch_cluster
B=$QCNN_ROOT/build/gls; mkdir -p "$B"
rq() { ssh "$H" "tcsh -c 'source $QUESTA >& /dev/null; cd $1; $2'"; }

case $STEP in
setup)
  ssh "$H" "mkdir -p $R/net $R/macros $R/sim"
  # server to server through this machine (pipe only, nothing stored locally)
  ssh "$SYNHOST" "cd $SYN && tar cf - snitch_cluster_wrapper.v snitch_cluster_wrapper.sdc run.env" | ssh "$H" "tar xf - -C $R/net"
  ssh "$SYNHOST" "cd $SYNMAC && tar cf - manifest.txt $MACV" | ssh "$H" "tar xf - -C $R/macros"
  # python venv for the verifiers: same one sim/ uses on tau1
  ssh "$H" "test -x $REMOTE_WORK/venv/bin/python" || \
    ssh "${GLS_VENV_HOST:-tau1}" "cd /tmp/ckp908/qcnn_work_sim && tar cf - venv" | ssh "$H" "tar xf - -C $REMOTE_WORK"
  "$QCNN_SIM/build_hw.sh" vsim
  ;;
compile)
  MODE=${2:?mode}; W=$R/$MODE
  ssh "$H" "mkdir -p $W"
  rsync -a "$G/mk_compile.py" "$G/gls_trace.sv" "$H:$W/"
  ssh "$H" "cd $W && sed '/^module snitch_cluster_wrapper/,\$d' $RTGT/generated/snitch_cluster_wrapper.sv > snitch_cluster_pkg.sv && \
    python3 mk_compile.py $RTGT/work-vsim/compile.vsim.tcl $MODE $W/snitch_cluster_pkg.sv $CELLS $R/net/snitch_cluster_wrapper.v \
      $W/gls_trace.sv $TCK_SDF $(for v in $MACV; do printf "$R/macros/%s " $v; done) > compile.tcl"
  case $MODE in
    rtl) VOPT="+acc" ;;
    zd)  VOPT="+nospecify +notimingchecks +acc=npr+gls_trace" ;;
    sdf) VOPT="+acc=npr+gls_trace -G/gls_trace/TCK_PS=$TCK_SDF -sdftyp /tb_bin/i_dut/i_snitch_cluster=$R/net/snitch_cluster_wrapper_idealclk.sdf.gz" ;;
  esac
  rq "$W" "rm -rf work; vlib work >& /dev/null; vsim -c -do \"source compile.tcl; quit\" >& compile.log; \
    grep -c Error: compile.log; vopt -work work $VOPT tb_bin gls_trace -o tb_gls >& vopt.log; tail -2 vopt.log"
  cat > "$B/launch_$MODE.sh" <<EOF
#!/bin/bash
# snitch_cluster.vsim equivalent for mode $MODE (called by the verifier: <elf> <ipc args>)
binary=\$(realpath \$1)
echo \$binary > .rtlbinary
vsim +permissive -t 1ps -64 -c -work $W/work -suppress 3009 $([ $MODE = sdf ] && echo "+no_notifier -suppress 16107,3448") \\
  -ldflags "-Wl,-rpath,$RTGT/work/lib -L$RTGT/work/lib -lfesvr -lutil" \\
  tb_gls +permissive-off ++\$binary ++\$2 -do "run -a"
EOF
  chmod +x "$B/launch_$MODE.sh"; rsync -a "$B/launch_$MODE.sh" "$H:$W/snitch_cluster.vsim"
  ;;
start)
  K=${2:?kernel}; MODE=${3:?mode}; W=$R/$MODE; RUN=$W/runs/$K
  APP= VERIFY=; source "$QCNN_SIM/kernels/$K.conf"
  LRUN=$SIM_BUILD/runs/$SIM_CFG/vsim/$K
  [ -f "$LRUN/build/$APP.elf" ] || { echo "no ELF: run sim/run_kernel.sh $K vsim first"; exit 1; }
  WS=$SIM_BUILD/ws/$SIM_CFG; v=$(eval echo "$VERIFY"); v=${v/#$WS/$RWS}; v=${v/#$QCNN_SIM/$REMOTE_WORK/qcnn_sim}
  ssh "$H" "rm -rf $RUN && mkdir -p $RUN/logs"
  rsync -a --exclude results/ "$QCNN_SIM/" "$H:$REMOTE_WORK/qcnn_sim/"
  rsync -a "$LRUN/build" "$H:$RUN/"
  cat > "$B/start_$MODE.sh" <<EOF
cd $RUN
tcsh -c 'source $QUESTA >& /dev/null; setenv SNITCH_WS $RWS; $REMOTE_WORK/venv/bin/python $v \\
  $W/snitch_cluster.vsim $RUN/build/$APP.elf --log sim.log --dump-results >& verify.log'
echo GLS_RC \$? >> verify.log
EOF
  rsync -a "$B/start_$MODE.sh" "$H:$RUN/start.sh"
  ssh "$H" "cd $RUN && (nohup sh start.sh > /dev/null 2>&1 &)"
  echo "started $K/$MODE on $H:$RUN"
  ;;
wait)
  K=${2:?kernel}; MODE=${3:?mode}; RUN=$R/$MODE/runs/$K
  for _ in $(seq 54); do ssh "$H" "grep -q GLS_RC $RUN/verify.log 2>/dev/null" && break; sleep 10; done
  ssh "$H" "tail -c 300 $RUN/sim.log 2>/dev/null; echo; tail -3 $RUN/verify.log; wc -l $RUN/logs/gls_hart_00000.txt 2>/dev/null"
  ssh "$H" "grep -q GLS_RC $RUN/verify.log" && echo GLS_DONE || echo GLS_RUNNING
  ;;
summary)
  K=${2:?kernel}; MODE=${3:?mode}; RUN=$R/$MODE/runs/$K; L=$B/runs/$MODE/$K
  REGIONS=; source "$QCNN_SIM/kernels/$K.conf"
  mkdir -p "$L"; rsync -a "$H:$RUN/logs" "$H:$RUN/sim.log" "$H:$RUN/verify.log" "$L/"
  rsync -a "$H:$RUN/results.csv" "$L/" 2>/dev/null || true
  python3 "$G/gls_summary.py" --kernel "$K" --mode "$MODE" --run "$L" --regions "$REGIONS" \
    --rtl "$B/runs/rtl/$K" --tck "$([ $MODE = sdf ] && echo $TCK_SDF || echo 1000)" --rtl-summary "$QCNN_SIM/results/${K}_vsim_$SIM_CFG.txt" | tee "$B/${K}_$MODE.txt"
  ;;
report)
  { echo "# Snitch cluster (fp_p5.0_wlm DC netlist) gate-level simulation, impl/snitch_cluster/gls/gls.sh"
    echo "# reference: sim/results/<kernel>_vsim_chimera_fp.txt (RTL, Questa 2022.1_2)"
    echo "# sdf: DC tt SDF, sdf_idealclk.py view (ideal clock + reset, 0.8 ns SDC input delay), README \"SDF run (tt)\""
    for f in "$B"/{gemm_fp64,conv2d}_{rtl,zd,sdf}.txt; do [ -f "$f" ] && { echo; cat "$f"; }; done
  } > "$G/results.txt"
  cat "$G/results.txt"
  ;;
sdf)
  # DC on $SYNHOST (detached; call again for the status), then the SDF goes to $H like the netlist
  SG=${GLS_SDFDIR:-/tmp/ckp908/qcnn_snitchgls_sdf}; FLOW=${GLS_FLOW:-/tmp/ckp908/qcnn/tree/flow/tsmc65}
  if ssh "$SYNHOST" "grep -q QC_SDF_DONE $SG/write_sdf.log 2>/dev/null && test ! -e $SG/snitch_cluster_wrapper_tt.sdf"; then
    ssh "$SYNHOST" "grep slack $SG/tt_timing.rpt; ls -la $SG/*.sdf.gz"
    ssh "$H" "test -s $R/net/snitch_cluster_wrapper_tt.sdf.gz" || \
      ssh "$SYNHOST" "cat $SG/snitch_cluster_wrapper_tt.sdf.gz" | ssh "$H" "cat > $R/net/snitch_cluster_wrapper_tt.sdf.gz"
    ssh "$SYNHOST" "cat $SG/clock_cells.txt" | ssh "$H" "cat > $R/net/clock_cells.txt"
    rsync -a "$G/sdf_idealclk.py" "$H:$R/net/"
    # input delay of the TB-driven ports = the SDC's set_input_delay (one value, min = max)
    IND=$(ssh "$H" "grep -o 'set_input_delay -clock [^ ]* *[0-9.]*' $R/net/snitch_cluster_wrapper.sdc | awk '{print \$NF}' | sort -u")
    [ "$(echo "$IND" | wc -l)" = 1 ] || { echo "expected one set_input_delay value, got: $IND"; exit 1; }
    ssh "$H" "cd $R/net && python3 sdf_idealclk.py snitch_cluster_wrapper_tt.sdf.gz clock_cells.txt $IND clk_i rst_ni | gzip -1 > snitch_cluster_wrapper_idealclk.sdf.gz"
    echo SDF_DONE; exit 0
  fi
  if ssh "$SYNHOST" "pgrep -u \$USER -f '[d]c_shell.*write_sdf' > /dev/null"; then
    ssh "$SYNHOST" "tail -2 $SG/write_sdf.log"; echo SDF_RUNNING; exit 0
  fi
  ssh "$SYNHOST" "mkdir -p $SG"; rsync -a "$G/write_sdf.tcl" "$SYNHOST:$SG/"
  DBTT=$(ssh "$SYNHOST" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
  ssh "$SYNHOST" "cd $SG && tcsh -f -c 'source $FLOW/site/site.csh; setenv QC_FLOW $FLOW; setenv SYN $SYN; \
    setenv SDF $SG/snitch_cluster_wrapper_tt.sdf; setenv QC_EXTRA_DB_TT \"$DBTT\"; \
    (nohup sh -c \"dc_shell -f write_sdf.tcl > write_sdf.log 2>&1; gzip -1 -f snitch_cluster_wrapper_tt.sdf\" >& /dev/null &)'"
  echo SDF_STARTED
  ;;
*) sed -n '2,16p' "$0"; exit 1 ;;
esac
