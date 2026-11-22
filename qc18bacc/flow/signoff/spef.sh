#!/usr/bin/env bash
# PrimeTime SPEF of a routed run for corners outside the P&R corners (flow/tsmc65 def2spef.py --escape-divider; the P&R
# corners' SPEFs come from run_pnr.sh):  qc18bacc/flow/signoff/spef.sh <tag> [corners, default ss]
#   -> $B/pnr/<tag>/out/<top>_<c>_pt.spef.  Env QC_SPEF_UNESC 1: unescaped conn names (R31; set by every block flow).
set -u
. "$(dirname "$0")/../common/env.sh"
tag=${1:?tag}; dir=$B/pnr/$tag
. "$ROOT/flow/tsmc65/common/tool.sh"; . "$dir/kit.env"; cd "$dir" || exit 1
export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
for c in ${2:-ss}; do
    cap=$(QC_FLOW=$FLOW tclsh <<<"proc qc_env {n {d {}}} {return \$d}; source $FLOW/site/site.tcl; source $FLOW/site/pnr.tcl; puts \$::QC_PNR_CAPDIR/\$::QC_PNR_CAPTABLE($c)")
    [ -f rc/$c.txt ] || "$PY" -I "$FLOW/pnr/py/captable_rc.py" "$LEF" "$cap" $c rc/$c
    "$PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" \
        --escape-divider > "def2spef_$c.log" 2>&1; echo "SPEF_DONE $c rc $? $(ls -la out/${TOP}_${c}_pt.spef | awk '{print $5}')"
done
