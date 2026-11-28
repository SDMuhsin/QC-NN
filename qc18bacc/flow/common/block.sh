# Shared driver of an ICC2 hard block (R92).  A block's run.sh sources common/env.sh and this file, sets the variables
# below and ends with  blk_main "$@"   (run.sh <step> <tag>; run dir $B/icc2/$BLK/<tag>; exit status non-zero when a
# tool or a gate of the step failed):
#   BLK block name   BLK_TOP top cell   BLK_SYN DC netlist tag ($B/syn/<tag>)   BLK_PERIOD clock period (ns) of P&R and
#   sign-off   BLK_CFG ICC2 block config (flow/icc2 QB_ICC2_CFG; export what it reads from the environment yourself)
#   BLK_PT PrimeTime sign-off script of one corner QC_CORNER (writes <run>/pt_blk_<corner>.txt; must return after its
#   design setup when ::QB_PT_SETUP_ONLY exists)   blk_pre_pnr <def>: writes the floorplan pin DEF <def> (run before
#   pnr's floorplan step: blk_pins)
#   BLK_FILL_SED BLK_ODPO_SED BLK_LVS_SED BLK_DRC_SED BLK_ANT_SED the deck edits of each Calibre mode (signoff/calibre/
#   cal.sh) as sed arguments ("-f <file>" ...); unset unless the block's run.sh sets them after sourcing this file (an
#   inherited value is dropped here; BLK_ANT_SED is optional, the others required), passed to cal.sh one per mode
#   (blk_fill_label, blk_calibre) and logged in BLK_KNOBS
#   BLK_GATES optional: the block's opt-in verdict gates, comma-separated (signoff/verdict.sh -g; the column's act gates)
#   BLK_INPUTS optional: the block's further inputs from outside the snapshot, "<key>=<file> ..." (blk_inputs records
#   their md5 after the DC inputs; the column's reference abstract, the regression block's DC database)
#   (BLK_GATES / BLK_INPUTS, like BLK_*_SED, are unset when this file is sourced: only the block's run.sh sets them)
# Steps:  pnr      ICC2 libs init floorplan place cts route outputs, then portcheck + fill; QC_PNR_FROM / QC_PNR_TO select
#                  a range, an unknown step name fails; a step init .. route drops the label of out/ and moves the
#                  ECO history out/eco aside (blk_unlabel), and so does a range that starts at outputs, once the route
#                  step's log passes (qb_icc2 -check, R111) and route completed after init .. cts (blk_done_order, R113);
#                  every precondition of the range is checked before anything is dropped or moved (blk_pnr_pre, R118:
#                  init on an existing design library fails with out/ intact);
#                  init records the md5 of its DC inputs in summary.txt once it succeeded (blk_inputs)
#         eco      sign-off ECO loop, at most QC_ECO_ROUNDS (common/env.sh) rounds: PrimeTime DMSA -> ICC2 eco -> outputs -> portcheck
#                  -> fill; ends when a round's pre-fix state is clean in every corner at zero margin; fails if it never
#                  is, if a round makes no progress (blk_eco_progress, R108: the pre-fix violation total shrinks, or
#                  stays and its setup + hold TNS improves), or at once if a sign-off check no ECO pass fixes
#                  is not clean (drv_eco.tcl prefix_unfixable, R103), or before ICC2 if PrimeTime made no change for a
#                  non-zero total (drv_eco.tcl eco_changes 0 and eco_ndr_nets 0, R116: the history line names the
#                  residual corner:check counts, eco_residual), or if a noise victim net a round routed with the
#                  spacing rule (icc2/common.tcl qb_eco_noise_ndr, R116) is unfixable again.  Fix guard-bands (env.sh): hold
#                  QC_ECO_HOLD_MARGIN, max_transition / max_capacitance QC_ECO_DRV_MARGIN, noise QC_ECO_NOISE_MARGIN;
#                  setup margin QC_ECO_SETUP_MARGIN (common/limits.txt, R108).
#                  The loop's history is out/eco/rounds.txt: a later eco step continues it (round number = position of
#                  the label of out/ in the chain route, eco, eco2, ...) and a recorded stop stays a stop unless
#                  QC_ECO_OVERRIDE_STOP=1, which is logged there and lets that one eco step run; the stop stands
#                  again unless a round of it applied its change list (blk_eco_stop, R114; "applied": ICC2 eco and
#                  outputs / portcheck / fill / extract of its label passed, the round's applied line, R115); a history
#                  with a round of out/'s chain without its applied line (written before R115) is refused (blk_eco_legacy,
#                  R117).  Every end of the loop before ICC2 marks the round's change list not applied (R117).
#                  Opt-in QC_ECO_PT_ONLY=1: the next round's PrimeTime
#                  DMSA only (record + history line, nothing applied; refuses a run with an unfinished label of out/)
#         fill     portcheck, Calibre dummy metal + OD / PO, fill-aware SPEFs of the label of out/ (first an unfinished
#                  one)                                                 calibre  LVS, DRC, antenna (fails on cal.sh's status)
#         post     PrimeTime sign-off + ETMs in every corner   views  abstract LEF + ETM scan   signoff  signoff/verdict.sh
#
# Details.  rundir <tag> (a further step) prints the run dir (common/queue.sh), verdict <tag> the signoff step's verdict
# without its record (read-only: common/regress.sh check), knobs <tag> the BLK_KNOBS line
# every step starts with (blk_knobs: flow root + flow knobs in force; also appended to the run's summary.txt, R115).  The label of out/ is out/label.txt
# (blk_out, written once outputs, portcheck, fill and SPEFs of the label passed): route, then eco, eco2, ... (one ICC2 label per ECO round, so every round's layout stays in the
# design library).  ECO round files: out/eco/<label>/ = what that round produced and nothing else (PrimeTime log + its .time,
# eco_summary.txt, change list + new-cell record [pt_eco.not_applied.* when the loop stopped before applying it],
# unfixable reasons, ICC2 log + its .time; an earlier attempt of the same round is kept as <label>.try<n>), out/eco/rounds.txt (one
# line per round and per stop / override: the history).
# Why a loop (R92, PI decision; r91b [M]): one zero-margin ECO pass predicted 0 violators in 9 corners and its own ECO
# route left 2 hold endpoints at -0.04 / -0.09 ps and one net 1.7 ps over max_transition, all on nets the ECO had not
# touched (264 hold endpoints within 5 ps of zero at wcl).  Convergence is judged by PrimeTime at the sign-off criterion
# (signoff/pt/drv_eco.tcl prefix_total: setup + hold + recovery + removal + max_transition + max_capacitance + noise, zero margin; and
# prefix_unfixable, R103: the other sign-off gates, which no ECO pass fixes), never at
# the fix margin; a round without progress (blk_eco_progress) is a bug to diagnose, so the step stops there.
blk_main() {
    local step=${1:?step} tag=${2:?tag}; d=$B/icc2/$BLK/$tag
    export QB_SYN=$BLK_SYN QB_PNR_PERIOD=$BLK_PERIOD QB_ICC2_CFG=$BLK_CFG QB_PIN_DEF=$d/pins.def
    case $step in
    rundir) echo "$d"; return 0 ;;
    knobs) blk_knobs "$step"; return 0 ;;
    # (R117; round-17 finding: common/regress.sh check re-ran the verdict as the signoff step, which appended its
    # BLK_KNOBS line to the run's summary.txt, so every check changed the record it checked) the verdict alone, read-only:
    # no BLK_STEP / BLK_KNOBS line, nothing written to the run dir
    verdict) blk_signoff; return ;;
    pnr|eco|fill|calibre|post|views|signoff) ;;
    *) sed '/^#$/,$d' "${BASH_SOURCE[0]}"; echo "BLK_FAIL $BLK: unknown step '$step'"; return 1 ;;
    esac
    echo "BLK_STEP $BLK $step $tag $(date +%T)"
    # (also in the run's summary.txt, R115: signoff/verdict.py flow_snapshot, every step of the run from one flow)
    mkdir -p "$d" && blk_knobs "$step" | tee -a "$d/summary.txt" || return 1
    "blk_$step" || { echo "BLK_FAIL $BLK $step $tag $(date +%T)"; return 1; }
    echo "BLK_DONE $BLK $step $tag $(date +%T)"
}
# The run's record of its settings (R103): one line per step, "BLK_KNOBS <blk> <step> <tag> flow <flow root> <name>=<value>
# ...": the flow the step runs (a snapshot's, common/deploy.sh) and the flow knobs in force (common/env.sh qb_knobs).
# Step "knobs" prints the line alone (common/regress.sh: in an empty environment = the snapshot's committed defaults).
# The deck edits are knobs too (R104; hunt round 9 on 018af5e: ant took the DRC deck's QB36_DRC_SED, which came from
# the environment and was recorded nowhere): BLK_KNOBS names every BLK_*_SED (paths in the flow as <flow>/...).
BLK_DECK_EDITS="BLK_FILL_SED BLK_ODPO_SED BLK_LVS_SED BLK_DRC_SED BLK_ANT_SED"
# (the optional BLK_GATES / BLK_INPUTS too, R109; hunt round 12: an inherited value reached the verdict's opt-in gates /
# the recorded inputs of a block that sets neither)
unset $BLK_DECK_EDITS BLK_GATES BLK_INPUTS
blk_knobs() { echo "BLK_KNOBS $BLK $1 $tag flow $QBF$(qb_knobs $BLK_DECK_EDITS)"; }
# PrimeTime environment of $BLK_PT, set in the subshell of the caller.  Nothing of DC's run.env (R100; [M] hunt on a06c97:
# it was sourced with set -a, and its QC_IO_PCT=20, written by flow/tsmc65 run_dc.sh, became an "environment override"
# of common/limits.txt in every PrimeTime session): the block's PrimeTime reads only the variables below, the sign-off
# limits come from limits.txt (or a deliberate experiment override in the caller's environment).
blk_pt_env() {
    qb_kit
    export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$BLK_PERIOD QC_PNR_OUT=$d QC_TOP=$BLK_TOP
    cd "$d"
}
blk_portcheck() {   # gate on the outputs netlist: ports as the DC netlist (names, directions, ranges: R103), no port-to-port assign (signoff/portcheck.py)
    local n; n=$(blk_input netlist) || return 1
    "$PY" -I "$QBF/signoff/portcheck.py" "$n" "$d/out/$BLK_TOP.v" "$BLK_TOP"
}
blk_pnr() {
    local all="libs init floorplan place cts route outputs" from=${QC_PNR_FROM:-libs} to=${QC_PNR_TO:-outputs} s l on=0
    for s in "$from" "$to"; do
        case " $all " in *" $s "*) ;; *) echo "BLK_FAIL pnr: unknown step '$s' (QC_PNR_FROM / QC_PNR_TO: $all)"; return 1 ;; esac
    done
    case "$all " in *"$to "*"$from "*) echo "BLK_FAIL pnr: QC_PNR_TO=$to is before QC_PNR_FROM=$from"; return 1 ;; esac
    # Every precondition of the range is checked before any step runs, i.e. before out/ is unlabelled or its ECO history
    # moved (R118; round-18 finding: a pnr re-run on a finished run dir dropped the label of out/ and moved out/eco, and
    # only then did init refuse the existing design library)
    l=$(blk_pnr_pre "$from" "$to") || { echo "$l"; return 1; }
    for s in $all; do
        [ "$s" = "$from" ] && on=1; [ $on = 1 ] || continue
        if [ "$s" = outputs ]; then
            # a range that starts at outputs relabels out/ to route (blk_pnr_pre: route passed and completed last); the ECO
            # history of the old label of out/ goes aside as in blk_unlabel
            if [ "$from" = outputs ]; then blk_unlabel outputs || return 1; fi
            blk_out route || return 1
        elif [ "$s" = libs ]; then blk_libs || return 1
        else
            blk_unlabel "$s" || return 1
            if [ "$s" = floorplan ]; then blk_pins || return 1; fi
            qb_icc2 "$d" "$s" || return 1
            if [ "$s" = init ]; then blk_inputs "$l" || return 1; fi
        fi
        [ "$s" = "$to" ] && break
    done
    tail -n 40 "$d/summary.txt"
}
# blk_pnr_pre <from> <to>: the preconditions of the pnr range <from> .. <to>, read-only (R118); prints the inputs line of
# blk_inputs when the range has init (blk_pnr records it once init passed), a BLK_FAIL line and status 1 otherwise:
#   init in the range   no design library <run>/<top>.nlib (icc2/init.tcl writes a new one only, R109) and every DC /
#                       BLK_INPUTS input there (blk_inputs)
#   floorplan in it     the block has its pin DEF writer blk_pre_pnr (blk_pins)
#   from floorplan .. route   the design library exists and the step before <from> passed (qb_icc2 -check)
#   from outputs        (R111; hunt round 13 on 1940fd4) the route step passed (qb_done saves the label before qb_icc2
#                       judges the step, so a route step that failed on an error under redirect left a saved route label)
#                       and (R113; hunt round 14 on f9f2580: a partial re-run place .. cts followed by a range from outputs
#                       relabelled the route label of the layout before) completed after every earlier step of its chain
#                       (blk_done_order: the completion record of common/env.sh qb_icc2)
blk_pnr_pre() {
    local from=$1 to=$2 all="libs init floorplan place cts route outputs" r= s p= on=0 l=
    for s in $all; do
        [ "$s" = "$from" ] && on=1; [ $on = 1 ] && r="$r $s"; [ "$s" = "$to" ] && break; [ $on = 1 ] || p=$s
    done
    if [[ " $r " == *" init "* ]]; then
        [ ! -e "$d/$BLK_TOP.nlib" ] || { echo "BLK_FAIL pnr init: design library $d/$BLK_TOP.nlib exists (init writes a new one only: a new run dir); nothing changed"; return 1; }
        l=$(blk_inputs) || { echo "$l"; return 1; }
    fi
    if [[ " $r " == *" floorplan "* ]] && ! declare -F blk_pre_pnr > /dev/null; then
        echo "BLK_FAIL pnr floorplan: the block has no blk_pre_pnr (pin DEF)"; return 1
    fi
    case $from in
    floorplan|place|cts|route)
        [ -e "$d/$BLK_TOP.nlib" ] || { echo "BLK_FAIL pnr $from: no design library $d/$BLK_TOP.nlib"; return 1; }
        qb_icc2 -check "$d" "$p" > /dev/null || { echo "BLK_FAIL pnr $from: the step before it, $p, did not pass ($(qb_icc2 -check "$d" "$p"))"; return 1; } ;;
    outputs)
        qb_icc2 -check "$d" route > /dev/null || { echo "BLK_FAIL pnr outputs: the route step did not pass ($(qb_icc2 -check "$d" route)): no outputs of label route"; return 1; }
        s=$(blk_done_order init:init floorplan:floorplan place:place cts:cts route:route) \
            || { echo "BLK_FAIL pnr outputs: route is not the last step of init .. route to complete ($s): no outputs of label route"; return 1; } ;;
    esac
    echo "$l"
}
# A pnr step that writes a design label (init .. route) rewrites route, which every label of out/ (route, eco, eco2, ...)
# is built from, so out/ is no longer the layout of its label: the label of out/ and an unfinished one are dropped before
# the step (R99; [M] hunt on 44735f5: QC_PNR_TO=route kept out/label.txt = route over the old out/, and post / calibre
# signed off the old layout).  A pnr range that ends with outputs writes the label of out/ again.
# The ECO history of the old layout (out/eco: rounds.txt and the round records) goes with it, moved aside to
# out/eco.pnr_<date_time> (R106; before, it stayed, so a stop of the old layout's loop stopped the new layout's eco).
blk_unlabel() {
    local a
    if [ -e "$d/out/eco" ]; then
        a=$d/out/eco.pnr_$(date +%Y%m%d_%H%M%S); [ ! -e "$a" ] || a=$a.$$
        mv "$d/out/eco" "$a" && echo "BLK_LABEL pnr $1 rewrites the layout: its ECO history out/eco moved to $a" || return 1
    fi
    [ -e "$d/out/label.txt" ] || [ -e "$d/out/label.new" ] || return 0
    echo "BLK_LABEL pnr $1 rewrites the layout: label of out/ $(cat "$d/out/label.txt" 2> /dev/null || echo none), unfinished $(cat "$d/out/label.new" 2> /dev/null || echo none): dropped"
    rm -f "$d/out/label.txt" "$d/out/label.new"
}
# The inputs of the pnr step from outside the snapshot (R100 [M] hunt on a06c97: nothing recorded which netlist a run was
# built from): one summary.txt line "init inputs syn <tag> netlist <md5> sdc <md5> run_env <md5> [<key> <md5> ...]" per
# successful init step: the DC inputs ($B/syn/$BLK_SYN: the netlist and DC SDC common/block_sdc.tcl reads, DC's run.env),
# then the block's own BLK_INPUTS (R101: the column's pin-reference abstract COL_REFLEF was recorded nowhere);
# common/regress.sh check compares the last line with the regression reference.
#   blk_inputs           prints the line of the inputs as they are now (before init)
#   blk_inputs <line>    after init succeeded: appends <line> to summary.txt, unless the inputs changed during init
# (R109; hunt round 12: the line was appended before init, so a failed init left a last line that blk_input then took for
# the layout's, which was built from the inputs before; icc2/init.tcl refuses an existing design library)
blk_input_list() { local s=$B/syn/$BLK_SYN; echo "netlist=$s/$BLK_TOP.v sdc=$s/$BLK_TOP.sdc run_env=$s/run.env ${BLK_INPUTS:-}"; }
blk_inputs() {
    local k f l="init inputs syn $BLK_SYN"
    for k in $(blk_input_list); do
        f=${k#*=}; [[ $k == [a-z]*=?* ]] || { echo "BLK_FAIL pnr init: input '$k' is not <key>=<file>"; return 1; }
        [ -f "$f" ] || { echo "BLK_FAIL pnr init: no input $f"; return 1; }
        l="$l ${k%%=*} $(md5sum < "$f" | cut -c1-32)"
    done
    if [ $# = 0 ]; then echo "$l"; return 0; fi
    [ "$l" = "$1" ] || { echo "BLK_FAIL pnr init: the inputs changed during init (before: $1; now: $l): nothing recorded"; return 1; }
    echo "$l" >> "$d/summary.txt" && echo "BLK_INPUTS $l"
}
# blk_input <key>: prints the file of input <key> (netlist, sdc, run_env or a BLK_INPUTS key) once its md5 equals the one
# the run recorded (the last "init inputs" line of summary.txt); fails otherwise.  Every reader of an input after init
# goes through it (R102; [M] hunt on b521ab0: blk_portcheck in every blk_out and the floorplan pin DEF read the DC
# netlist again unchecked, so a re-synthesised netlist could be compared / pinned against a layout built from another)
blk_input() {
    local k f= r m
    for k in $(blk_input_list); do [ "${k%%=*}" = "$1" ] && f=${k#*=}; done
    [ -n "$f" ] || { echo "BLK_FAIL input '$1' is not an input of $BLK (common/block.sh blk_input_list)" >&2; return 1; }
    r=$(grep '^init inputs ' "$d/summary.txt" 2> /dev/null | tail -n 1 | awk -v k="$1" '{ for (i = 5; i < NF; i += 2) if ($i == k) print $(i + 1) }')
    [ -n "$r" ] || { echo "BLK_FAIL input $1: no md5 recorded in $d/summary.txt (pnr init records it: blk_inputs)" >&2; return 1; }
    m=$(md5sum < "$f" | cut -c1-32) && [ "$m" = "$r" ] \
        || { echo "BLK_FAIL input $1 $f: md5 ${m:-none}, recorded at init $r (changed since the run was built)" >&2; return 1; }
    echo "$f"
}
# The floorplan pin DEF of the run, QB_PIN_DEF = <run>/pins.def (the block config's P(PIN_DEF)): written by the block's
# blk_pre_pnr right before each floorplan step, as <def>.part renamed into place (R99; before, $B/icc2/<blk>/pins*.def:
# one file per host that every pnr rewrote in place, so concurrent runs raced and a later floorplan re-run read another
# run's pins)
# (the block has a blk_pre_pnr: blk_pnr_pre)
blk_pins() {
    mkdir -p "$d" && rm -f "$QB_PIN_DEF.part" && blk_pre_pnr "$QB_PIN_DEF.part" && mv -f "$QB_PIN_DEF.part" "$QB_PIN_DEF" \
        && echo "BLK_PINS $QB_PIN_DEF md5 $(md5sum < "$QB_PIN_DEF" | cut -c1-12)"
}
# libs step under the host's NDM build lock (R97; [M] two pnr runs of one snapshot collided on the shared NDM build):
# a concurrent libs step waits for the build, then reuses its NDM (flow/icc2/libs.tcl builds it atomically).  flock
# drops the lock when its holder dies, so a killed build never blocks the next one.
blk_libs() {
    local k=$B/icc2/ndm/.build.lock
    mkdir -p "${k%/*}" || return 1
    ( flock -n 9 || { echo "BLK_LIBS waiting for the NDM build lock $k $(date +%T)"; flock 9; } || exit 1
      qb_icc2 "$d" libs icc2_lm_shell ) 9> "$k"
}
# The label of out/ (R96: one atomic set per label).  out/label.txt names the ICC2 label whose outputs (flow/icc2/
# outputs.tcl), portcheck, Calibre fill and fill-aware SPEFs out/ holds; it exists only once all of them passed for that
# label.  While a label's set is being written there is no out/label.txt and out/label.new says "<label> <stage>", the
# stage to run next: outputs, or fill (= portcheck, fill, extract).  The fill step and the next eco step finish such a
# label first (blk_pending); post, calibre and views refuse a run without a label of out/.  (Before, outputs.tcl wrote
# label.txt ahead of portcheck / fill: after a fill failure the next eco round ran on the new netlist with the SPEFs of
# the label before.)
blk_label() {   # prints the label of out/; fails when there is none
    local l; l=$(cat "$d/out/label.txt" 2> /dev/null)
    if [ -n "$l" ]; then echo "$l"; return 0; fi
    echo "BLK_FAIL no label of out/ (out/label.txt); unfinished: $(cat "$d/out/label.new" 2> /dev/null || echo none) (run.sh fill or eco finishes it)" >&2
    return 1
}
blk_out() {   # blk_out <label> [outputs|fill]: out/ for <label> from that stage on, then <label> is the label of out/
    local l=$1 s=${2:-outputs} n=$d/out/label.new
    mkdir -p "$d/out" && rm -f "$d/out/label.txt" || return 1
    if [ "$s" = outputs ]; then { echo "$l outputs" > "$n" && QB_ICC2_LABEL=$l qb_icc2 "$d" outputs && blk_out_md5 "$l"; } || return 1; fi
    { echo "$l fill" > "$n" && blk_portcheck && blk_fill_label "$l"; } || return 1
    echo "$l" > "$n.tmp" && mv -f "$n.tmp" "$d/out/label.txt" && rm -f "$n" && echo "BLK_LABEL $l is the label of out/"
}
# The layout identity of a label (R110): one summary.txt line "outputs_md5 <label> netlist <md5> def <md5> pg <md5> gds
# <md5>" per outputs of the label, md5 of its out/ netlist, DEF, PG netlist (the LVS source's input; R114, hunt round 15:
# it was in no record) and GDS (the fill's input; R115, round-16 hunt: in no record either; blk_fill_label checks out/
# against it) without the writers' comment lines (date, user, the write command with the run dir) and GDS time stamps
# (common/gds_md5.py); common/regress.sh compares the route label's with the reference of a 1-core run (ICC2 repeatable)
blk_out_sums() {   # "netlist <md5> def <md5> pg <md5> gds <md5>" of out/ as it is now
    local o=$d/out/$BLK_TOP n f p g
    n=$(set -o pipefail; grep -v '^//' "$o.v" | md5sum | cut -c1-32) \
        && f=$(set -o pipefail; gzip -dc "$o.def.gz" | grep -v '^#' | md5sum | cut -c1-32) \
        && p=$(set -o pipefail; grep -v '^//' "${o}_pg.v" | md5sum | cut -c1-32) \
        && g=$("$PY" -I "$QBF/common/gds_md5.py" "$o.gds") || { echo "BLK_FAIL outputs md5 of $o.v / .def.gz / _pg.v / .gds" >&2; return 1; }
    echo "netlist $n def $f pg $p gds $g"
}
blk_out_md5() {
    local s; s=$(blk_out_sums) || return 1
    echo "outputs_md5 $1 $s" >> "$d/summary.txt" && echo "BLK_OUT_MD5 $1 $s"
}
# blk_out_check <label>: one OUT_MD5 line; status 0 when out/ now has the md5 of the last "outputs_md5 <label>" line
# (out/ is the outputs of that label: views before the abstract, R114)
blk_out_check() {
    local r s
    r=$(awk -v l="$1" '$1 == "outputs_md5" && $2 == l { $1 = $2 = ""; r = $0 } END { sub(/^ +/, "", r); print r }' "$d/summary.txt" 2> /dev/null)
    s=$(blk_out_sums) || s=missing
    [ -n "$r" ] && [ "$r" = "$s" ] && { echo "OUT_MD5 $1 PASS out/ = its outputs record: $s"; return 0; }
    echo "OUT_MD5 $1 FAIL out/ now: $s; record: ${r:-none}"; return 1
}
# The completion order of ICC2 steps (R113): blk_done_order <step>:<label> ...: one BLK_ORDER line; status 0 when each
# has an "icc2_done <step> <label>" line in summary.txt (common/env.sh qb_icc2: written when the step passed) and the last
# such line of each comes after the last one of the one before it (line order of the append-only summary.txt = order of
# completion; content, not file times).  common/block.sh blk_pnr (a range from outputs), signoff/verdict.py step_order.
blk_done_order() {
    awk -v want="$*" 'BEGIN { n = split(want, w, " ") } $1 == "icc2_done" { p[$2 ":" $3] = NR }
        END { for (i = 1; i <= n; i++) { x = (w[i] in p) ? p[w[i]] : 0; s = s " " w[i] "@" (x ? x : "none"); if (!x || x <= y) b = 1; y = x }
              printf "BLK_ORDER %s summary.txt line of the last icc2_done of each, increasing:%s\n", b ? "FAIL" : "ok", s; exit b }' "$d/summary.txt" 2> /dev/null \
        || { [ -f "$d/summary.txt" ] || echo "BLK_ORDER FAIL no $d/summary.txt"; return 1; }
}
# The content chain of the sign-off files (R113; hunt round 14 on f9f2580: the freshness gates compared file times only,
# which a run dir copied without its times does not keep): each consumer step records the md5 of the files it read and
# of the files it wrote, as one summary.txt line "chain <step> <corner|-> label <label> <file>=<md5> ..." (files relative
# to the run dir):  fill  out GDS -> dummy metal, filled GDS, dummy OD / PO, LVS / DRC GDS, fill DEF;  extract  netlist +
# fill DEF -> SPEF of every corner;  pt <corner>  netlist + SPEF -> its report and log;  etm <corner>  netlist + SPEF ->
# ETM .lib / .db / ref;  lvs  LVS / DRC GDS + LVS source -> lvs.rep;  drc, ant  the GDS -> summary report;  abstract
# (views, R114)  the DEF of the label of out/ -> abstract LEF.  The inputs'
# md5 are taken before the step and must be the same after it.  blk_chain_check (views: the ETMs; signoff/verdict.py
# md5_<step>) holds a record against the files as they are now.
blk_md5() {   # blk_md5 <file> ...: "<file>=<md5> ..." of those files of the run dir; fails on a missing one
    local f l=
    for f; do
        [ -f "$d/$f" ] || { echo "BLK_FAIL chain: no $d/$f" >&2; return 1; }
        l="$l $f=$(md5sum < "$d/$f" | cut -c1-32)"
    done
    echo "${l# }"
}
blk_chain() {   # blk_chain <step> <corner|-> <label> <blk_md5 of the inputs before the step> <output file> ...
    local s=$1 c=$2 l=$3 i=$4 n o w; shift 4
    n=$(blk_md5 $(for w in $i; do echo "${w%=*}"; done)) && [ -n "$i" ] && [ "$n" = "$i" ] \
        || { echo "BLK_FAIL chain $s $c: the inputs changed during the step (before: ${i:-none}; now: ${n:-missing}): nothing recorded"; return 1; }
    o=$(blk_md5 "$@") || return 1
    echo "chain $s $c label $l $i $o" >> "$d/summary.txt"
}
# blk_chain_check <step> <corner|-> <label>: one CHAIN line; status 0 when the last "chain <step> <corner>" line is of
# <label> and every file it names has its recorded md5 now, 2 without such a line, 1 otherwise
blk_chain_check() {
    local s=$1 c=$2 l=$3 r w f m bad=
    r=$(awk -v s="$s" -v c="$c" '$1 == "chain" && $2 == s && $3 == c { r = $0 } END { print r }' "$d/summary.txt" 2> /dev/null)
    [ -n "$r" ] || { echo "CHAIN $s $c MISSING no 'chain $s $c' line in summary.txt"; return 2; }
    set -- $r; [ "$4 $5" = "label $l" ] || bad=" label:${5:-none}(want:$l)"; shift 5
    for w; do f=${w%=*}; m=$([ -f "$d/$f" ] && md5sum < "$d/$f" | cut -c1-32); [ "${m:-none}" = "${w##*=}" ] || bad="$bad $f"; done
    [ -z "$bad" ] && [ $# -gt 0 ] && { echo "CHAIN $s $c PASS label $l: $# files = the md5 the step recorded"; return 0; }
    echo "CHAIN $s $c FAIL label / md5 changed since the step:${bad:- no file}"; return 1
}
blk_pending() {   # finishes the unfinished label of out/ (out/label.new), if there is one (an ECO label: its round applied)
    local l s
    [ -f "$d/out/label.new" ] || return 0
    read -r l s < "$d/out/label.new"
    case $s in outputs|fill) ;; *) echo "BLK_FAIL out/label.new '$l $s' is not '<label> outputs|fill'"; return 1 ;; esac
    echo "BLK_LABEL finishing the unfinished label $l of out/ from its $s stage"
    blk_out "$l" "$s" && blk_eco_applied "$l"
}
# fill step: the unfinished label of out/ if there is one, else the label of out/ again (portcheck, fill, extract)
blk_fill() {
    local l
    if [ -f "$d/out/label.new" ]; then blk_pending; else l=$(blk_label) && blk_out "$l" fill; fi
}
# Calibre dummy metal + dummy OD / PO of out/<top>.gds; metal -> DEF FILLS -> fill-aware SPEFs of every sign-off corner
# (flow/icc2/extract.tcl on label $1, the label out/ was written from)
# blk_die_window <def.gz>: "xLB yLB xRT yRT" (um) of the DEF DIEAREA (a rectangle or, as ICC2 writes it, a polygon: its
# bounding box), exact: integer database units (UNITS DISTANCE MICRONS, a power of 10) written as decimals with as many
# digits as the unit has (R107; hunt round 11 on d1978e1: awk's %s printed 6 significant digits, 1043.285 -> 1043.29).
# Fails without a DIEAREA of integer points or with another unit.
blk_die_window() {
    zcat "$1" | awk '$1 == "UNITS" && $2 == "DISTANCE" && $3 == "MICRONS" { u = $4 }
        function dec(x,   s, m) { s = x < 0 ? "-" : ""; x = x < 0 ? -x : x; if (k == 0) return s x
            m = sprintf("%0" (k + 1) "d", x); return s substr(m, 1, length(m) - k) "." substr(m, length(m) - k + 1) }
        $1 == "DIEAREA" { n = 0
        if (u !~ /^1(0)*$/) exit 1
        k = length(u) - 1
        for (i = 2; i <= NF; i++) if ($i ~ /^-?[0-9]+$/) v[n++] = $i + 0; else if ($i !~ /^[();]$/) exit 1
        if (n < 4 || n % 2) exit 1
        x0 = x1 = v[0]; y0 = y1 = v[1]
        for (i = 2; i + 1 < n; i += 2) { x0 = v[i] < x0 ? v[i] : x0; x1 = v[i] > x1 ? v[i] : x1; y0 = v[i+1] < y0 ? v[i+1] : y0; y1 = v[i+1] > y1 ? v[i+1] : y1 }
        printf "%s %s %s %s\n", dec(x0), dec(y0), dec(x1), dec(y1); ok = 1; exit }
        END { exit !ok }'
}
blk_fill_label() {
    local l=$1 o=$d/calibre C=$QBF/signoff/calibre w i t=out/$BLK_TOP c cs s=; mkdir -p "$o"
    # out/ is the outputs of label $l (blk_out_check: its outputs record, GDS included, R115), so the fill record's input
    # GDS / DEF md5 are of that label's outputs
    blk_out_check "$l" || return 1
    cs=$(qb_corners) && i=$(blk_md5 "$t.gds" "$t.def.gz") || return 1
    # chip window of both fill decks = the DEF DIEAREA (blk_die_window) -> calibre/die_window.sed.  Metal too since R99
    # (signoff/calibre/fill_blk.sed ChipWindowUsed; [M] rgr rg44735f5a: without a window the metal fill took the drawn
    # extent, y 4.76 .. 124.04 of the 130-um die, and stopped 7.3 / 8.5 um short of the bottom / top edge, the OD / PO
    # fill 0.6 um)
    w=$(blk_die_window "$d/out/$BLK_TOP.def.gz") || { echo "BLK_FAIL no DIEAREA of integer points in a UNITS DISTANCE MICRONS 10^k out/$BLK_TOP.def.gz"; return 1; }
    set -- $w; [ $# = 4 ] || { echo "BLK_FAIL no DIEAREA in out/$BLK_TOP.def.gz"; return 1; }
    # (+ its results in the deck copy, R109: signoff/calibre/cal.sh cal_deck)
    { printf 's#^VARIABLE xLB .*#VARIABLE xLB %s#\ns#^VARIABLE yLB .*#VARIABLE yLB %s#\ns#^VARIABLE xRT .*#VARIABLE xRT %s#\ns#^VARIABLE yRT .*#VARIABLE yRT %s#\n' "$@"
      printf '#@expect ^VARIABLE xLB %s$\n#@expect ^VARIABLE yLB %s$\n#@expect ^VARIABLE xRT %s$\n#@expect ^VARIABLE yRT %s$\n' "${1//./\\.}" "${2//./\\.}" "${3//./\\.}" "${4//./\\.}"
    } > "$o/die_window.sed"
    QB55_FILL_SED=$BLK_FILL_SED QB55_WINDOW=$o/die_window.sed bash "$C/cal.sh" fill "$d/out/$BLK_TOP.gds" "$BLK_TOP" "$o/fill" > "$o/fill.log" 2>&1 \
        || { cat "$o/fill.log"; return 1; }
    grep -v '^CAL55_fill' "$o/fill.log"
    # dummy OD / PO (R77) on the metal-filled GDS (signoff/calibre/odpo_blk.sed) -> odpo/<top>_fill.gds: the GDS of
    # Calibre LVS / DRC / antenna (calibre step).  FEOL dummies only: no effect on the metal SPEFs.
    QB77_ODPO_SED=$BLK_ODPO_SED QB55_WINDOW=$o/die_window.sed bash "$C/cal.sh" odpo "$o/fill/${BLK_TOP}_fill.gds" "$BLK_TOP" "$o/odpo" > "$o/odpo.log" 2>&1 \
        || { cat "$o/odpo.log"; return 1; }
    cat "$o/odpo.log"
    ( . "$C/kl.sh"; kl_run "$C/fill_def.py" -rd gds="$o/fill/DM.gds" -rd design="$BLK_TOP" -rd out="$d/out/${BLK_TOP}_fill.def" ) || return 1
    # (+ the chip window both decks read, R118; round-18 finding: die_window.sed was in no record)
    blk_chain fill - "$l" "$i" calibre/die_window.sed calibre/fill/DM.gds "calibre/fill/${BLK_TOP}_fill.gds" calibre/odpo/DODPO.gds "calibre/odpo/${BLK_TOP}_fill.gds" "${t}_fill.def" || return 1
    i=$(blk_md5 "$t.v" "${t}_fill.def") || return 1
    QB_ICC2_LABEL=$l qb_icc2 "$d" extract || return 1
    for c in $cs; do s="$s ${t}_${c}_pt.spef.gz"; done
    blk_chain extract - "$l" "$i" $s || return 1
    grep '^extract' "$d/summary.txt" | tail -n 4
}
# ICC2 label of the ECO round that starts from label $1 / number of rounds that built label $1
blk_eco_label() { case $1 in route) echo eco ;; eco) echo eco2 ;; eco[1-9]*) echo "eco$(( ${1#eco} + 1 ))" ;; *) return 1 ;; esac; }
blk_eco_index() { case $1 in route) echo 0 ;; eco) echo 1 ;; eco[1-9]*) echo "${1#eco}" ;; *) return 1 ;; esac; }
# The loop's history out/eco/rounds.txt (R115; round-16 finding [M] tau11 col/r101: a round's change-list line was
# written before ICC2 eco ran, and a round whose ICC2 eco then failed (rc 1, "failed after the change list") lifted the
# stop and set the previous total all the same).  Per round "ECO round <k> <date> label <from> prefix_total <n>: change
# list -> label <to> prefix_tns <t>" (the PrimeTime half: the fixes chosen, nothing applied yet), then, only once ICC2
# eco AND blk_out of <to> passed (in that round, or when blk_pending finishes the label later), "ECO round <k> <date>
# label <from> applied -> label <to>" (blk_eco_applied).  Only an applied line makes a round count.
blk_eco_applied() {   # blk_eco_applied <label>: the applied line of the round whose change list built <label> (none: nothing)
    local h=$d/out/eco/rounds.txt w
    w=$(awk -v l="$1" '$9 == "change" && $10 == "list" && $11 == "->" && $13 == l { w = $3 " " $6 } END { print w }' "$h" 2> /dev/null)
    [ -n "$w" ] || return 0
    set -- "$1" $w
    echo "ECO round $2 $(date +%F_%T) label $3 applied -> label $1" | tee -a "$h"
}
# The loop's stop rule (R108).  blk_eco_prev <history> <label>: "<prefix_total> [<prefix_tns>]" of the round that built
# <label> (its change-list line), once that round applied (R115: its applied line); nothing for route, for a round that
# never applied, or after an override line (a stop overridden since).  The TNS field is appended to the change-list
# line, so the fields up to the label keep their places; a history line written before R108 has none.
blk_eco_prev() {
    [ -f "$1" ] || return 0
    awk -v l="$2" '$2 == "override" { p = "" }
        $9 == "change" && $10 == "list" && $11 == "->" { c[$13] = $8; sub(":", "", c[$13]); if ($14 == "prefix_tns") c[$13] = c[$13] " " $15 }
        $7 == "applied" && $8 == "->" && $10 == l && ($10 in c) { p = c[$10] }
        END { print p }' "$1"
}
# blk_eco_progress <total> <tns> [<previous total> [<previous tns>]]: status 0 when this round's pre-fix state is progress
# over the previous round's: no previous round, a smaller violator total, or an equal total and a setup + hold TNS better
# by more than QB_ECO_TNS_EPS ns (a round that fixes most of the slack of the same violators, e.g. the ECO route moving a
# few endpoints from -10 to -0.5 ps, is progress the count alone does not see; R108 [M] rgr rg039bd31a: one round of
# fixes left the count where it was).  Otherwise status 1 and the reason on stdout.  No TNS of the previous round (a
# pre-R108 history line): the count alone.
QB_ECO_TNS_EPS=0.001
blk_eco_progress() {
    local n=$1 t=$2 pn=${3:-} pt=${4:-}
    [ -n "$pn" ] && [ "$n" -ge "$pn" ] || return 0
    if [ "$n" = "$pn" ] && [ -n "$pt" ] && awk -v t="$t" -v p="$pt" -v e="$QB_ECO_TNS_EPS" 'BEGIN { exit !(t > p + e) }'; then return 0; fi
    echo "not smaller than the previous round's $pn$([ "$n" = "$pn" ] && echo ", TNS $t ns not better than its ${pt:-(not recorded)} by more than $QB_ECO_TNS_EPS ns")"
    return 1
}
# blk_eco_unapplied <round dir>: the round's change list is not applied (no next label): marked in its record, gone from out/eco
blk_eco_unapplied() {
    local f; for f in pt_eco.tcl pt_eco_cells.txt pt_eco_ndr.txt; do [ -f "$1/$f" ] && mv "$1/$f" "$1/${f%.*}.not_applied.${f##*.}"; rm -f "$d/out/eco/$f"; done
}
# blk_eco_ruled <label>: the nets the rounds that built <label> set the noise spacing rule on (R116; their ICC2 eco
# records out/eco/<label>/pt_eco_ndr_set.txt, flow/icc2/common.tcl qb_eco_noise_ndr), one per line
blk_eco_ruled() {
    local i n; n=$(blk_eco_index "$1") || return 1
    for ((i = 1; i <= n; i++)); do cat "$d/out/eco/$([ $i = 1 ] && echo eco || echo "eco$i")/pt_eco_ndr_set.txt" 2> /dev/null; done
    return 0
}
# blk_eco_stop <history>: the stop line in force, nothing when there is none.  A stop (a ": FAIL " round line) stands until
# a later round applied its change list (its applied line, R115; before, its change-list line, written before ICC2 eco
# ran); an override line does not end it (R114; hunt round 15 on f8f6eee: the override line was written before
# PrimeTime ran and ended the stop for good, so after a failed or a PrimeTime-only overridden round a plain eco step
# resumed past the stop)
blk_eco_stop() {
    [ -f "$1" ] || return 0
    awk '/: FAIL / { s = $0 } $7 == "applied" && $8 == "->" { s = "" } END { print s }' "$1"
}
# blk_eco_judge: the PrimeTime half's verdict on the round (blk_eco's variables: e h k from to max prev; sets tot tns):
# status 0 = apply the change list, 3 = the loop ends without failure (converged, or PrimeTime only), anything else = a
# stop (its history line written here, or a BLK_FAIL line); blk_eco marks the round's change list not applied whenever
# it is not 0 (R117)
# blk_eco_legacy <history>: the ECO labels of out/'s finished chain (eco .. the label of out/; with an unfinished label,
# up to the round before it) that have a change-list line in the history and no applied line (R117; round-17 finding:
# a history written before R115 has no applied lines [tau08 col/r102], so blk_eco_prev gave no previous total and the
# progress rule was silently off when such a run went on).  Every round of a later history that built a label of out/
# has its applied line (blk_eco_applied right after blk_out), so any label printed means a history the loop cannot read.
blk_eco_legacy() {
    local l x n
    if [ -f "$d/out/label.new" ]; then read -r l x < "$d/out/label.new"; n=$(( $(blk_eco_index "$l" || echo 1) - 1 ))
    else l=$(cat "$d/out/label.txt" 2> /dev/null); n=$(blk_eco_index "$l" || echo 0); fi
    [ -f "$1" ] || return 0
    awk -v n="$n" '$9 == "change" && $10 == "list" && $11 == "->" { c[$13] = 1 } $7 == "applied" && $8 == "->" { a[$10] = 1 }
        END { for (i = 1; i <= n; i++) { l = (i == 1 ? "eco" : "eco" i); if ((l in c) && !(l in a)) { printf "%s%s", s, l; s = " " } } }' "$1"
}
blk_eco_judge() {
    local un ch nd rep why
    cat "$e/eco_summary.txt"
    tot=$(awk '$1 == "prefix_total" { print $2; exit }' "$e/eco_summary.txt")
    case $tot in ''|*[!0-9]*) echo "BLK_FAIL eco: no prefix_total in out/eco/eco_summary.txt"; return 1 ;; esac
    # the sign-off's gates no ECO pass fixes (R103, drv_eco.tcl prefix_unfixable: non-zero ones end the loop; before, a
    # round with prefix_total 0 was "converged" and the post step failed on them)
    tns=$(awk '$1 == "prefix_tns" { print $2; exit }' "$e/eco_summary.txt")
    # (a number in any form Tcl prints, R118; round-18 finding: "0" or "-2" without a decimal point failed the round)
    [[ $tns =~ ^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$ ]] || { echo "BLK_FAIL eco: no numeric prefix_tns in out/eco/eco_summary.txt ('$tns')"; return 1; }
    un=$(awk '$1 == "prefix_unfixable" { print $2; exit }' "$e/eco_summary.txt")
    case $un in ''|*[!0-9]*) echo "BLK_FAIL eco: no prefix_unfixable in out/eco/eco_summary.txt"; return 1 ;; esac
    # opt-in QC_ECO_PT_ONLY=1: this round's PrimeTime half only (a check of the PT side, e.g. on a copy of a run): the
    # record and a history line, no verdict on the loop, nothing applied
    if [ "${QC_ECO_PT_ONLY:-}" = 1 ]; then
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: PrimeTime only (QC_ECO_PT_ONLY=1), prefix_unfixable $un, change list not applied" | tee -a "$h"
        return 3
    fi
    if [ "$un" != 0 ]; then
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL $un sign-off check count(s) the ECO cannot fix: $(awk '$1 == "prefix_unfixable"' "$e/eco_summary.txt" | sed 's/^[^(]*(//; s/)$//' | cut -c1-300)" | tee -a "$h"
        return 1
    fi
    if [ "$tot" = 0 ]; then
        echo "ECO round $k $(date +%F_%T) label $from prefix_total 0: converged" | tee -a "$h"
        grep '^eco' "$d/summary.txt" | tail -n 20; return 3
    fi
    if [ "$k" -gt "$max" ]; then
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL not converged after $max rounds" | tee -a "$h"; return 1
    fi
    # PrimeTime made no change (R116; [M] tau08 col/r102 round 3: one ml_rcb noise victim, driver a flop, unfixable
    # reasons I Q, an empty change list, and ICC2 eco failed in qb_eco_nets): nothing for ICC2, the loop stops here.
    # Its unfixable noise victims' nets (pt_eco_ndr.txt) count as a change: ICC2 routes them with the spacing rule
    # (flow/icc2/common.tcl qb_eco_noise_ndr); one that is a victim again after a round ruled it ends the loop
    ch=$(awk '$1 == "eco_changes" { print $2; exit }' "$e/eco_summary.txt")
    case $ch in ''|*[!0-9]*) echo "BLK_FAIL eco: no eco_changes in out/eco/eco_summary.txt"; return 1 ;; esac
    nd=$(awk '$1 == "eco_ndr_nets" { print $2; exit }' "$e/eco_summary.txt")
    [[ $nd =~ ^[0-9]+$ ]] && [ "$(grep -c . "$e/pt_eco_ndr.txt" 2> /dev/null)" = "$nd" ] \
        || { echo "BLK_FAIL eco: no eco_ndr_nets in out/eco/eco_summary.txt or not the nets of out/eco/pt_eco_ndr.txt"; return 1; }
    rep=$(blk_eco_ruled "$from" | sort -u | comm -12 - <(sort -u "$e/pt_eco_ndr.txt"))
    if [ -n "$rep" ]; then
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL unfixable: $(echo $rep | wc -w) noise victim net(s) with the spacing rule already set: $(echo $rep | cut -c1-300) (see out/eco/$to/*drc_noise.txt)" | tee -a "$h"
        return 1
    fi
    if [ "$ch" = 0 ] && [ "$nd" = 0 ]; then
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL PrimeTime made no change; unfixable: $(sed -n 's/^eco_residual \([^(]*\) (.*/\1/p' "$e/eco_summary.txt" | head -n 1 | cut -c1-300); noise nets ICC2 cannot rule: $(sed -n 's/^eco_ndr_excluded \([0-9]*\) (.*: \(.*\))$/\1 \2/p' "$e/eco_summary.txt" | head -n 1 | cut -c1-200) (see out/eco/$to/*drc_*.txt)" | tee -a "$h"
        return 1
    fi
    if ! why=$(blk_eco_progress "$tot" "$tns" $prev); then
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL $why" | tee -a "$h"
        return 1
    fi
    return 0
}
blk_eco() {
    local max=$QC_ECO_ROUNDS e=$d/out/eco h k from to a tot tns prev r j f cs n stop
    cs=$(qb_corners) || return 1   # (assigned first: a command substitution in an assignment prefix hides the status)
    h=$e/rounds.txt; mkdir -p "$e"
    # The history decides (R92 review; before, a second eco step forgot the stop and the previous total): a recorded stop
    # ends every later eco step too, unless it is overridden explicitly, which the history then says (blk_eco_stop: an
    # override lasts until a round applies a change list)
    # a history the loop cannot read (blk_eco_legacy, R117): refused, before anything runs; its run is continued by hand
    # only after its rounds are checked (each round's ICC2 eco log and the outputs / fill of its label) and their applied
    # lines appended, or the loop starts again from a new layout (pnr).  Not in the PrimeTime-only mode, which neither
    # judges progress nor lifts a stop
    stop=$(blk_eco_legacy "$h")
    if [ -n "$stop" ] && [ "${QC_ECO_PT_ONLY:-}" != 1 ]; then
        echo "BLK_FAIL eco: history $h has a change-list line but no applied line for label(s) $stop of out/'s chain (written before R115, or a round cut off between its label and its applied line): the loop cannot tell which rounds applied, refused"
        return 1
    fi
    stop=$(blk_eco_stop "$h")
    if [ -n "$stop" ]; then
        if [ "${QC_ECO_OVERRIDE_STOP:-}" != 1 ]; then
            echo "BLK_FAIL eco: the loop of this run has stopped ($h):"; echo "$stop"
            echo "  QC_ECO_OVERRIDE_STOP=1 continues from label $(cat "$d/out/label.txt" 2> /dev/null) and is logged there"; return 1
        fi
        echo "ECO override $(date +%F_%T) of the stop above (QC_ECO_OVERRIDE_STOP=1; this eco step, the stop stands again unless a round of it applies its change list)" | tee -a "$h"
    fi
    # an unfinished label of out/ (a round that failed after its ICC2 eco) is finished before any PrimeTime round; not in
    # the PrimeTime-only mode, which changes nothing of out/ (R113; hunt round 14 on f9f2580: it ran outputs / fill /
    # extract here first): it refuses such a run
    if [ "${QC_ECO_PT_ONLY:-}" = 1 ] && [ -e "$d/out/label.new" ]; then
        echo "BLK_FAIL eco: QC_ECO_PT_ONLY=1 on an unfinished label of out/ ($(cat "$d/out/label.new")): run.sh fill or eco finishes it first"; return 1
    fi
    blk_pending || { echo "ECO $(date +%F_%T) the unfinished label of out/ ($(cat "$d/out/label.new")) failed again" | tee -a "$h"; return 1; }
    while :; do
        from=$(blk_label) || return 1
        to=$(blk_eco_label "$from") || { echo "BLK_FAIL eco: no ECO label after '$from' (out/label.txt)"; return 1; }
        k=$(( $(blk_eco_index "$from") + 1 ))
        prev=$(blk_eco_prev "$h" "$from")
        # the round's record holds only what this round produces: an earlier attempt of the round is kept aside and the
        # files of the round before leave out/eco (not the history)
        a=$e/$to
        if [ -d "$a" ]; then n=1; while [ -e "$a.try$n" ]; do n=$((n + 1)); done; mv "$a" "$a.try$n"; fi
        mkdir -p "$a"
        for f in "$e"/*.txt "$e"/*.tcl "$e"/*.log; do [ "$f" = "$h" ] || rm -f "$f"; done
        # PrimeTime DMSA on the outputs of label $from: pre-fix state of every corner at the sign-off criterion, then the
        # change list, unless that state is clean (converged) or this is the check after the last round (QB_ECO_CHECK)
        ( blk_pt_env || exit 1
          QB_ECO_CHECK=$(( k > max )) QB_PT_SCRIPT=$BLK_PT QB_ECO_CORNERS=$cs QB_ECO_NLIB=$d/$BLK_TOP.nlib \
              QB_ECO_BLOCK=$BLK_TOP/$from qb_pt -nosignoff pt_eco.log pt_shell -multi_scenario -f "$QBF/signoff/pt/drv_eco.tcl" ); r=$?
        rm -f "$e"/work/.eco_ndm_*   # (the DMSA workers' NDM copies, ~0.42 GB each: disk, R71; their logs stay)
        for f in "$d/pt_eco.log" "$d/pt_eco.log.time" "$e"/*.txt "$e"/*.tcl "$e"/*.log; do [ -f "$f" ] && [ "$f" != "$h" ] && cp "$f" "$a/"; done
        # (R117; round-17 finding: the unfixable and not-converged stops left the round's change list as if to be applied)
        # every end of the loop before ICC2 (a stop, PrimeTime only, converged) marks the round's change list not applied
        # (blk_eco_unapplied; no list: nothing to mark)
        j=1; [ $r = 0 ] && { blk_eco_judge; j=$?; }
        if [ $j != 0 ]; then blk_eco_unapplied "$a"; [ $j = 3 ]; return; fi
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: change list -> label $to prefix_tns $tns" | tee -a "$h"
        # ICC2: the change list on label $from -> $to (name / load / legality gates, ECO route, route gate), then out/ for
        # label $to (blk_out: outputs, portcheck, fill, extract; only then is $to the label of out/ and the round applied)
        # (the log with its .time: signoff/verdict.py icc2_log checks the ICC2 eco step of every ECO label of out/'s
        # chain from the round record, qb_icc2 -check, R111)
        QB_ECO_FROM=$from QB_ECO_TO=$to qb_icc2 "$d" eco; r=$?; cp "$d/eco.log" "$d/eco.log.time" "$a/"
        [ $r = 0 ] && blk_out "$to" && blk_eco_applied "$to" \
            || { echo "ECO round $k $(date +%F_%T) label $from: failed after the change list (label of out/: $(cat "$d/out/label.txt" 2> /dev/null || echo none), unfinished: $(cat "$d/out/label.new" 2> /dev/null || echo none))" | tee -a "$h"; return 1; }
    done
}
# On the filled GDS of the fill step (metal: the one the SPEFs saw; + OD / PO): LVS source, Calibre LVS, DRC (block deck),
# antenna -> <run>/calibre.  All three run; the step fails on any cal.sh exit status (LVS not CORRECT, an LVS ERC result
# or a NOT EXECUTED ERC check signoff/calibre/erc_allow.txt does not allow, any DRC / antenna result: signoff/calibre/cal.sh).
blk_calibre() {
    local o=$d/calibre C=$QBF/signoff/calibre g r=0 l i m q; g=$o/odpo/${BLK_TOP}_fill.gds
    l=$(blk_label) || return 1
    # the filled GDS is the fill step's of the label of out/, from out/<top>.gds as it is now: the fill record (blk_chain_check
    # fill: out GDS + DEF -> the filled GDS ..., R115; before, file times: $g newer than out/<top>.gds)
    blk_chain_check fill - "$l" || { echo "BLK_FAIL the fill record of label $l does not hold (run.sh fill)"; return 1; }
    bash "$C/lvs_src.sh" "$d/out/${BLK_TOP}_pg.v" "$o/${BLK}_src.spi" > "$o/src.log" 2>&1; r=$?; tail -n 3 "$o/src.log"; [ $r = 0 ] || return 1
    i=$(blk_md5 "calibre/odpo/${BLK_TOP}_fill.gds" "calibre/${BLK}_src.spi") || return 1
    # (R118; round-18 finding: a chain line was written over the reports of an earlier run when Calibre failed) the
    # reports of the earlier run go first (blk_cal_reports of the deck copies there), and a mode's chain line is written
    # only when its cal.sh passed
    rm -f "$o/lvs/lvs.rep" $(blk_cal_reports lvs:lvs:ERC drcb:drc:DRC ant:ant:DRC) || return 1
    for m in lvs:lvs drcb:drc ant:ant; do
        case ${m#*:} in
        lvs) QB36_LVS_SED=$BLK_LVS_SED bash "$C/cal.sh" lvs "$g" "$BLK_TOP" "$o/${BLK}_src.spi" "$o/lvs" ;;
        drc) QB36_DRC_SED=$BLK_DRC_SED bash "$C/cal.sh" drc "$g" "$BLK_TOP" "$o/drcb" ;;
        ant) QB36_ANT_SED=${BLK_ANT_SED:-} bash "$C/cal.sh" ant "$g" "$BLK_TOP" "$o/ant" ;;
        esac > "$o/${m%:*}.log" 2>&1; q=$?
        cat "$o/${m%:*}.log"
        [ $q = 0 ] || { echo "BLK_FAIL calibre ${m#*:}: cal.sh exit status $q: no chain line"; r=1; continue; }
        # the content chain (blk_chain): LVS from the GDS + source, DRC / antenna from the GDS (their summary report: the
        # deck copy's DRC SUMMARY REPORT)
        if [ "${m#*:}" = lvs ]; then blk_chain lvs - "$l" "$i" calibre/lvs/lvs.rep || r=1; continue; fi
        q=$(blk_cal_reports "$m:DRC"); q=${q#"$d/"}
        [ -n "$q" ] && blk_chain "${m#*:}" - "$l" "${i%% *}" "$q" \
            || { echo "BLK_FAIL chain ${m#*:}: no DRC SUMMARY REPORT file in the deck dir of calibre/${m%:*}/deck.${m#*:}"; r=1; }
    done
    return $r
}
# blk_cal_reports <dir>:<mode>:<DRC|ERC> ...: the summary report file the deck copy calibre/<dir>/deck.<mode> names (its
# "<DRC|ERC> SUMMARY REPORT" line: a file in the deck dir), one path per deck copy that names one
blk_cal_reports() {
    local w q
    for w; do
        q=$(sed -n "s/^${w##*:} SUMMARY REPORT *\"\\([^\"/]*\\)\".*/\\1/p" "$d/calibre/${w%%:*}/deck.$(cut -d: -f2 <<< "$w")" 2> /dev/null | head -n 1)
        [ -z "$q" ] || echo "$d/calibre/${w%%:*}/$q"
    done
}
# PrimeTime in every sign-off corner on the ICC2 netlist + SPEF (fails on any setup / hold / DRV / noise / min pulse width
# / min period violator, common/env.sh qb_pt), then the ETMs of every corner (R71; fails on MEXT-6 / MEXT-80 (R111) / MEXT-81 / MEXT-97)
blk_post() {
    local l; l=$(blk_label) || return 1
    ( blk_pt_env || exit 1
      cs=$(qb_corners) || exit 1; r=0
      for c in $cs; do   # every corner is reported before a failure stops the step (R67)
          # (the content chain, blk_chain: netlist + SPEF of the corner -> its report and log, recorded only when the
          # session passed; R115, round-16 hunt: a failed session got its chain line, over a report of an earlier
          # session it had not removed)
          rm -f "pt_blk_$c.txt" "pt_blk_$c.log" "pt_blk_$c.log.time"
          i=$(blk_md5 "out/$BLK_TOP.v" "out/${BLK_TOP}_${c}_pt.spef.gz") || { r=1; continue; }
          if QC_CORNER=$c qb_pt "pt_blk_$c.log" pt_shell -f "$BLK_PT"; then
              cat "pt_blk_$c.txt"; blk_chain pt "$c" "$l" "$i" "pt_blk_$c.txt" "pt_blk_$c.log" || r=1
          else cat "pt_blk_$c.txt" 2> /dev/null; r=1; fi
      done
      [ $r = 0 ] || exit 1
      for c in $cs; do
          # the corner's ETM files are this session's (R104; hunt round 9 on 018af5e: the .db was only counted over
          # out/etm, so an older one passed): removed first, then each there and none older than the one before; their
          # content chain: netlist + SPEF of the corner -> .lib / .db / ref (blk_chain; views checks it), recorded only
          # when the session and these checks passed (R115)
          e=out/etm/${BLK_TOP}_$c; rm -f "$e.lib" "${e}_lib.db" "${e}_ref.txt"
          i=$(blk_md5 "out/$BLK_TOP.v" "out/${BLK_TOP}_${c}_pt.spef.gz") || { r=1; continue; }
          q=0; QC_CORNER=$c qb_pt -nosignoff "etm_$c.log" pt_shell -f "$QBF/signoff/etm/etm.tcl" || q=1
          ! blk_etm_warnings "etm_$c.log" | head -n 3 | grep . || { echo "ETM $c: table limit / port aggressor filter / driving cell / feedthrough warnings"; q=1; }
          [ -s "$e.lib" ] && [ -s "${e}_lib.db" ] && [ -s "${e}_ref.txt" ] && ! [ "${e}_lib.db" -ot "$e.lib" ] && ! [ "${e}_ref.txt" -ot "${e}_lib.db" ] \
              || { echo "ETM $c: $e.lib / _lib.db / _ref.txt missing, empty or out of order"; q=1; }
          [ $q = 0 ] && blk_chain etm "$c" "$l" "$i" "$e.lib" "${e}_lib.db" "${e}_ref.txt" || r=1
          echo "ETM $c $(grep -c 'RC-011' "etm_$c.log") RC-011 lines"
      done; exit $r )
}
# blk_etm_warnings <log>: the lines of an ETM extraction log with a message the ETM must not have, by its exact ID
# "(MEXT-6)" table limit, "(MEXT-80)" port aggressor filter (R111), "(MEXT-81)" driving cell, "(MEXT-97)" feedthrough
# (R118; round-18 finding: the pattern matched longer IDs too, e.g. MEXT-61 / MEXT-810); signoff/verdict.py etm_log
blk_etm_warnings() { grep -E '\(MEXT-(6|80|81|97)\)' "$1"; }
# Views for the chip top: ICC2 abstract LEF with port antenna data + antenna / abutment / PG pin gates (flow/icc2/
# abstract.tcl, on the label of out/, which it records in summary.txt for signoff/verdict.py) -> out/<top>.lef; ETM
# gate (signoff/etm/etmcheck.py: against the netlist reference of the same session) of the post step's ETMs
blk_views() {
    local c cs own i
    cs=$(qb_corners) || return 1
    own=$(blk_label) || return 1
    # (R99; was a warning since R92) the abstract is of the layout of out/ only: an inherited QB_ICC2_LABEL naming
    # another label fails
    if [ -n "${QB_ICC2_LABEL:-}" ] && [ "$QB_ICC2_LABEL" != "$own" ]; then
        echo "BLK_FAIL views: QB_ICC2_LABEL=$QB_ICC2_LABEL is not the label of out/ ($own)"; return 1
    fi
    echo "BLK_VIEWS abstract of label $own = the label of out/"
    # (R114; hunt round 15 on f8f6eee: the LEF was in no content record, only the mtime gate fresh_abstract linked it)
    # the content chain of the abstract (blk_chain): out/ is the outputs of the label (blk_out_check), its DEF -> the LEF
    blk_out_check "$own" || return 1
    i=$(blk_md5 "out/$BLK_TOP.def.gz") || return 1
    QB_ICC2_LABEL=$own QB_PY=$PY qb_icc2 "$d" abstract || return 1
    blk_chain abstract - "$own" "$i" "out/$BLK_TOP.lef" || return 1
    grep '^abstract' "$d/summary.txt" | tail -n 3
    # (R113; hunt round 14 on f9f2580: the ETMs of out/etm were scanned whatever layout they were of) each corner's ETMs
    # are the post step's of the label of out/, unchanged since (blk_chain_check etm)
    for c in $cs; do
        blk_chain_check etm "$c" "$own" || return 1
        "$PY" -I "$QBF/signoff/etm/etmcheck.py" "$d/out/etm/${BLK_TOP}_$c.lib" || return 1
    done
}
# The machine verdict of the run dir (signoff/verdict.sh: every sign-off gate re-read from the run's files; one GATE line
# per gate, last line SIGNOFF <top> PASS|FAIL): its exit status is the step's
blk_signoff() {
    local v=$QBF/signoff/verdict.sh
    [ -f "$v" ] || { echo "BLK_FAIL signoff: $v missing"; return 1; }
    bash "$v" ${BLK_GATES:+-g "$BLK_GATES"} -b "$BLK" "$d" "$BLK_TOP" || return 1
}
