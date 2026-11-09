#!/usr/bin/env bash
# QC18-ACC zero-delay gate-level simulation of the full network (VCS) on the DC netlist of qc18acc/impl/run.sh, run
# from the local repo (like hw/sim/run_rtl.sh, whose export it reuses):
#   qc18acc/gls/run_gls.sh start [host=usask] [syn_tag=qa_w3.5] [first_image=0] [n_images=1]
#   qc18acc/gls/run_gls.sh check [host=usask] [syn_tag=qa_w3.5]       (status, or result when finished)
#   qc18acc/gls/run_gls.sh sdf   [host=usask] [syn_tag=qa_w3.5]       (tt SDF for QA_SDF=1; call until it lists it)
# start: rsync $QC_LOCAL/export_rtl (hw/sim/run_rtl.sh export, with names.txt) to <host>, git pull the host-local
#   clone, generate the TB backdoor include (gen_snap.py) from $QC_RDIR/build/syn/<tag>/qa_top.v, then in the
#   background flow/tsmc65/sim/run_vcs.sh with QC_GLS=1 (tcbn65gplus cell models, +nospecify +notimingcheck), the
#   macro Verilog models (hw/tech/macros_sim.f), qa_tb +define+QA_GLS+QA_SAIF: maps (backdoor) and logits (host port)
#   checked per image like the RTL run, SAIF of the whole DUT over START..DONE of the first image.
# check: fetch sim.log to $QC_LOCAL/gls_<tag>.log, print the result, compare the per-image / per-pass cycles with the
#   RTL log ($QC_LOCAL/rtl_sim.log).  Remote: $QC_RDIR/build/sim/gls_<tag>/ (sim.log, vcs.log),
#   SAIF $QC_RDIR/gls/<tag>/qa_top_img<first>.saif (stays on the host).
# sdf: DC write_sdf.tcl (tt lib + macro tt .db, synthesis WLM; detached, ~5 min) -> $QC_RDIR/gls/<tag>/sdf/qa_top_tt.sdf,
#   then flow/tsmc65/sim/sdf_idealclk.py (ideal clock = the CKLNQD ICGs, ideal reset tree, input delay QA_SDF_IND ns,
#   default 0.5 = 20 % of the 2.5 ns TB clock, the SDC's IO rule) -> qa_top_tt_idealclk.sdf (what QA_SDF=1 annotates).
# QA_SDF=1 (start / check): timing-annotated run (build gls_<tag>_sdf, SAIF qa_top_img<first>_sdf.saif): VCS
#   -sdf typ:qa_tb.dut:<idealclk sdf>, cell + ARM macro specify blocks and timing checks ON, +no_notifier (a
#   violation is reported in sim.log, counted by check, but does not X the register / macro word).
# Environment: QC_RDIR (default /tmp/ckp908/qc18acc), QC_LOCAL (default /tmp/root/qc18acc).
set -eu
CMD=${1:?start|check}; HOST=${2:-usask}; T=${3:-qa_w3.5}; IMG0=${4:-0}; NIMG=${5:-1}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
LOC=${QC_LOCAL:-/tmp/root/qc18acc}
EXP=$LOC/export_rtl
G=$RDIR/gls/$T
SDFD=$G/sdf; SDFI=$SDFD/qa_top_tt_idealclk.sdf
SFX=""; VOPT="+define+QA_GLS+QA_SAIF +incdir+$G"; GLSV=1
if [ "${QA_SDF:-0}" = 1 ]; then
    SFX=_sdf; GLSV=0      # run_vcs.sh QC_GLS=1 would add +nospecify +notimingcheck: cells added here instead
    VOPT="$VOPT -v \$QC_CELL_V +define+QC_GLS -sdf typ:qa_tb.dut:$SDFI +no_notifier +sdfverbose"
fi
case "$CMD" in
start)
    [ -f "$EXP/names.txt" ] || { echo "no $EXP/names.txt: run qc18acc/hw/sim/run_rtl.sh first"; exit 1; }
    [ -z "$SFX" ] || ssh "$HOST" "test -s $SDFI" || { echo "no $SDFI: run_gls.sh sdf $HOST $T"; exit 1; }
    ssh "$HOST" "mkdir -p $RDIR/export_rtl $G"
    rsync -a --delete "$EXP/" "$HOST:$RDIR/export_rtl/"
    ssh "$HOST" "set -e; cd $RDIR/repo && git pull -q --ff-only && git log -1 --format='%h %s'
      N=$RDIR/build/syn/$T/qa_top.v; test -f \$N || { echo no netlist \$N; exit 1; }
      python3 -I qc18acc/gls/gen_snap.py \$N > $G/qa_gls_snap.svh; head -1 $G/qa_gls_snap.svh
      . flow/tsmc65/site/sram.sh; export QC_MC_OUT QA_NETLIST=\$N QC_BUILD=$RDIR/build QC_GLS=$GLSV
      export QC_VCS_OPTS='$VOPT' QC_PASS_RE='RESULT PASS' QC_FAIL_RE='RESULT FAIL|MISMATCH|Error|Fatal'
      export QC_SIM_OPTS='+DIR=$RDIR/export_rtl +IMG0=$IMG0 +NIMG=$NIMG +SAIF=$G/qa_top_img$IMG0$SFX.saif'
      nohup flow/tsmc65/sim/run_vcs.sh gls_$T$SFX qa_tb qc18acc/gls/gls.f qc18acc/hw/tech/macros_sim.f qc18acc/hw/tb/tb.f > $G/run$SFX.log 2>&1 < /dev/null &
      echo GLS started on \$(hostname -s): $RDIR/build/sim/gls_$T$SFX" ;;
check)
    S=$RDIR/build/sim/gls_$T$SFX
    if ssh "$HOST" "pgrep -f '[r]un_vcs.sh gls_$T$SFX ' > /dev/null"; then
        ssh "$HOST" "echo running; tail -c 300 $S/sim.log 2>/dev/null || tail -3 $S/vcs.log"; exit 0
    fi
    ssh "$HOST" "cat $G/run$SFX.log; ls -la $G/*.saif 2>/dev/null; grep -i -E 'sdf|annotat' $S/vcs.log | head -8" || true
    scp -q "$HOST:$S/sim.log" "$LOC/gls_$T$SFX.log" || { ssh "$HOST" "grep -E 'Error' -A3 $S/vcs.log | head -20"; exit 1; }
    grep -E "^(TB|IMAGE|PERF|RESULT|MAP|SAIF)|MISMATCH|Error" "$LOC/gls_$T$SFX.log" | head -40
    # timing-check messages (QA_SDF=1): count per check type and per first-level instance
    grep -A1 'Timing violation' "$LOC/gls_$T$SFX.log" | grep -oE '\$(setuphold|setup|hold|width|period|recrem)[^,]*|qa_tb\.dut\.[^ .]*' |
        sed -E 's/\(.*//' | sort | uniq -c | sort -rn | head -12 | sed 's/^/  timing: /'
    echo "  timing violations: $(grep -c 'Timing violation' "$LOC/gls_$T$SFX.log")"
    python3 - "$LOC/gls_$T$SFX.log" "$LOC/rtl_sim.log" <<'PY'
import re, sys
def cyc(p):
    t = open(p).read()
    return {(m[0], m[1]): m[2] for m in re.findall(r"^PASSCYC img (\d+) pass (\d+) \S+\s+(\d+)", t, re.M)} | \
           {(m[0], "total"): m[1] for m in re.findall(r"^PERF img (\d+) total (\d+)", t, re.M)}
g, r = cyc(sys.argv[1]), cyc(sys.argv[2])
diff = [k for k in g if k in r and g[k] != r[k]]
imgs = sorted({k[0] for k in g})
print(f"CYCLES gate-level vs RTL: images {','.join(imgs)}, {len(g)} counters compared, {len(diff)} differ"
      + "".join(f"; img {k[0]} {k[1]}: {g[k]} vs {r[k]}" for k in diff[:5])
      + "".join(f"; img {i} total {g[(i, 'total')]}" for i in imgs if (i, 'total') in g))
PY
    ;;
sdf)
    SYN=$RDIR/build/syn/$T
    if ssh "$HOST" "test -s $SDFI"; then ssh "$HOST" "cat $SDFD/idealclk.log; grep -m2 slack $SDFD/tt_timing.rpt; ls -la $SDFI"; exit 0; fi
    if ssh "$HOST" "pgrep -u \$USER -f '[d]c_shell -f write_sdf.tcl' > /dev/null"; then
        ssh "$HOST" "tail -2 $SDFD/write_sdf.log"; echo SDF_RUNNING; exit 0
    fi
    if ssh "$HOST" "grep -q QC_SDF_DONE $SDFD/write_sdf.log 2>/dev/null"; then
        ssh "$HOST" "set -e; cd $RDIR/repo; python3 flow/tsmc65/sim/sdf_idealclk.py --clock-celltype CKLNQD \
          $SDFD/qa_top_tt.sdf ${QA_SDF_IND:-0.5} clk rst_n > $SDFI.tmp 2> $SDFD/idealclk.log; mv $SDFI.tmp $SDFI
          cat $SDFD/idealclk.log; ls -la $SDFD"; exit 0
    fi
    DBTT=$(ssh "$HOST" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
    ssh "$HOST" "set -e; mkdir -p $SDFD; cd $RDIR/repo && git pull -q --ff-only; cp qc18acc/gls/write_sdf.tcl $SDFD/
      cd $SDFD; tcsh -f -c 'source $RDIR/repo/flow/tsmc65/site/site.csh; setenv QC_FLOW $RDIR/repo/flow/tsmc65; \
      setenv SYN $SYN; setenv SDF $SDFD/qa_top_tt.sdf; setenv QC_SDC $RDIR/repo/qc18acc/impl/constraints.sdc; \
      setenv QC_PERIOD 3.3; setenv QC_EXTRA_DB_TT \"$DBTT\"; \
      (nohup dc_shell -f write_sdf.tcl >& write_sdf.log &)'"
    echo SDF_STARTED ;;
*) sed -n 2,22p "$0"; exit 1 ;;
esac
