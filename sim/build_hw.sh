#!/usr/bin/env bash
# Build the snitch_cluster standalone testbench for one simulator.
#   sim/build_hw.sh <vlt|vsim> [cfg]
#   vlt  : local Verilator 5.x      -> build/sim/ws/<cfg>/target/snitch_cluster/bin/snitch_cluster.vlt
#   vsim : Questa on $REMOTE_HOST    -> $REMOTE_WORK/ws/<cfg>/target/snitch_cluster/bin/snitch_cluster.vsim
source "$(dirname "$0")/lib/common.sh"
SIM=${1:?usage: build_hw.sh <vlt|vsim> [cfg]}
CFG=${2:-$SIM_CFG}
require_ws "$CFG"
TGT=$(tgt_dir "$CFG")
JOBS=${JOBS:-$(nproc)}

# Config-dependent generated RTL/TB sources (clustergen) - always produced locally.
gen_sources() {
  tb_make "$CFG" "$TGT/generated/snitch_cluster_wrapper.sv" "$TGT/generated/bootdata.cc" \
                 "$TGT/generated/memories.json" "$TGT/generated/link.ld"
}

case "$SIM" in
  vlt)
    [ -x "${VERILATOR:-}" ] || die "Verilator not found (set VERILATOR=...)"
    gen_sources
    tb_make "$CFG" -j"$JOBS" VLT="$VERILATOR" VLT_ROOT="$VERILATOR_ROOT" \
      VERILATOR_ROOT="$VERILATOR_ROOT" bin/snitch_cluster.vlt
    ;;
  vsim)
    gen_sources
    # Questa compile script from bender, with ROOT pointing at the remote copy.
    RWS=$(remote_ws "$CFG")
    TCL=$SIM_BUILD/compile.vsim.$CFG.tcl
    (cd "$TGT" && "$BENDER" script vsim -t rtl -t snitch_cluster -t test -t simulation -t vsim \
       --vlog-arg="-svinputport=compat -override_timescale 1ns/1ps -suppress 2583 -suppress 13314 -64 -work work-vsim/ ") \
      | sed "s|^set ROOT .*|set ROOT \"$RWS\"|" > "$TCL"
    log "syncing workspace to $REMOTE_HOST:$RWS"
    ssh "$REMOTE_HOST" "mkdir -p $RWS $REMOTE_WORK/shims"
    rsync -a --delete --exclude '.git/' --exclude 'target/snitch_cluster/work*/' \
      --exclude 'target/snitch_cluster/bin/' --exclude 'target/snitch_cluster/logs/' \
      "$(ws_dir "$CFG")/" "$REMOTE_HOST:$RWS/"
    rsync -a "$SIM_BUILD/shims/" "$TCL" "$REMOTE_HOST:$REMOTE_WORK/shims/"
    # fesvr is rebuilt on the host (RHEL8 gcc), the rest is the upstream vsim recipe.
    remote_questa "cd $RWS/target/snitch_cluster && rm -rf work-vsim && \
      make BENDER=$REMOTE_WORK/shims/bender-replay BENDER_REPLAY_TCL=$REMOTE_WORK/shims/$(basename "$TCL") \
      bin/snitch_cluster.vsim >& vsim_build.log; tail -3 vsim_build.log; test -x bin/snitch_cluster.vsim"
    ;;
  *) die "unknown simulator '$SIM' (vlt|vsim)";;
esac
log "hardware ready: $SIM / $CFG"
