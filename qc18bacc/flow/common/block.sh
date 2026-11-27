# Shared driver of an ICC2 hard block (R92).  A block's run.sh sources common/env.sh and this file, sets the variables
# below and ends with  blk_main "$@"   (run.sh <step> <tag>; run dir $B/icc2/$BLK/<tag>; exit status non-zero when a
# tool or a gate of the step failed):
#   BLK block name   BLK_TOP top cell   BLK_SYN DC netlist tag ($B/syn/<tag>)   BLK_PERIOD clock period (ns) of P&R and
#   sign-off   BLK_CFG ICC2 block config (flow/icc2 QB_ICC2_CFG; export what it reads from the environment yourself)
#   BLK_PT PrimeTime sign-off script of one corner QC_CORNER (writes <run>/pt_blk_<corner>.txt; must return after its
#   design setup when ::QB_PT_SETUP_ONLY exists)   blk_pre_pnr <def>: writes the floorplan pin DEF <def> (run before
#   pnr's floorplan step: blk_pins)
#   BLK_FILL_SED BLK_ODPO_SED BLK_LVS_SED BLK_DRC_SED Calibre deck seds as sed arguments ("-f <file>" ...)
#   BLK_GATES optional: the block's opt-in verdict gates, comma-separated (signoff/verdict.sh -g; the column's act gates)
#   BLK_INPUTS optional: the block's further inputs from outside the snapshot, "<key>=<file> ..." (blk_inputs records
#   their md5 after the DC inputs; the column's reference abstract)
# Steps:  pnr      ICC2 libs init floorplan place cts route outputs, then portcheck + fill; QC_PNR_FROM / QC_PNR_TO select
#                  a range, an unknown step name fails; a step init .. route drops the label of out/ (blk_unlabel);
#                  init first records the md5 of its DC inputs in summary.txt (blk_inputs)
#         eco      sign-off ECO loop, at most QC_ECO_ROUNDS (4) rounds: PrimeTime DMSA -> ICC2 eco -> outputs -> portcheck
#                  -> fill; ends when a round's pre-fix state is clean in every corner at zero margin; fails if it never
#                  is, or if the pre-fix violation total does not shrink.  Fix guard-bands (env.sh): hold
#                  QC_ECO_HOLD_MARGIN, max_transition / max_capacitance QC_ECO_DRV_MARGIN, noise QC_ECO_NOISE_MARGIN.
#                  The loop's history is out/eco/rounds.txt: a later eco step continues it (round number = position of
#                  the label of out/ in the chain route, eco, eco2, ...) and a recorded stop stays a stop unless
#                  QC_ECO_OVERRIDE_STOP=1, which is logged there.  Opt-in QC_ECO_PT_ONLY=1: the next round's PrimeTime
#                  DMSA only (record + history line, nothing applied)
#         fill     portcheck, Calibre dummy metal + OD / PO, fill-aware SPEFs of the label of out/ (first an unfinished
#                  one)                                                 calibre  LVS, DRC, antenna (fails on cal.sh's status)
#         post     PrimeTime sign-off + ETMs in every corner   views  abstract LEF + ETM scan   signoff  signoff/verdict.sh
#
# Details.  rundir <tag> (a further step) prints the run dir (common/queue.sh).  The label of out/ is out/label.txt
# (blk_out, written once outputs, portcheck, fill and SPEFs of the label passed): route, then eco, eco2, ... (one ICC2 label per ECO round, so every round's layout stays in the
# design library).  ECO round files: out/eco/<label>/ = what that round produced and nothing else (PrimeTime log,
# eco_summary.txt, change list + new-cell record [pt_eco.not_applied.* when the loop stopped before applying it],
# unfixable reasons, ICC2 log; an earlier attempt of the same round is kept as <label>.try<n>), out/eco/rounds.txt (one
# line per round and per stop / override: the history).
# Why a loop (R92, PI decision; r91b [M]): one zero-margin ECO pass predicted 0 violators in 9 corners and its own ECO
# route left 2 hold endpoints at -0.04 / -0.09 ps and one net 1.7 ps over max_transition, all on nets the ECO had not
# touched (264 hold endpoints within 5 ps of zero at wcl).  Convergence is judged by PrimeTime at the sign-off criterion
# (signoff/pt/drv_eco.tcl prefix_total: setup + hold + max_transition + max_capacitance + noise, zero margin), never at
# the fix margin; a total that does not shrink is a bug to diagnose, so the step stops there.
blk_main() {
    local step=${1:?step} tag=${2:?tag}; d=$B/icc2/$BLK/$tag
    export QB_SYN=$BLK_SYN QB_PNR_PERIOD=$BLK_PERIOD QB_ICC2_CFG=$BLK_CFG QB_PIN_DEF=$d/pins.def
    case $step in
    rundir) echo "$d"; return 0 ;;
    pnr|eco|fill|calibre|post|views|signoff) ;;
    *) sed '/^#$/,$d' "${BASH_SOURCE[0]}"; echo "BLK_FAIL $BLK: unknown step '$step'"; return 1 ;;
    esac
    echo "BLK_STEP $BLK $step $tag $(date +%T)"
    "blk_$step" || { echo "BLK_FAIL $BLK $step $tag $(date +%T)"; return 1; }
    echo "BLK_DONE $BLK $step $tag $(date +%T)"
}
# PrimeTime environment of $BLK_PT, set in the subshell of the caller.  Nothing of DC's run.env (R100; [M] hunt on a06c97:
# it was sourced with set -a, and its QC_IO_PCT=20, written by flow/tsmc65 run_dc.sh, became an "environment override"
# of common/limits.txt in every PrimeTime session): the block's PrimeTime reads only the variables below, the sign-off
# limits come from limits.txt (or a deliberate experiment override in the caller's environment).
blk_pt_env() {
    qb_kit
    export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$BLK_PERIOD QC_PNR_OUT=$d QC_TOP=$BLK_TOP
    cd "$d"
}
blk_portcheck() {   # gate on the outputs netlist: port bits as the DC netlist, no port-to-port assign (signoff/portcheck.py)
    "$PY" -I "$QBF/signoff/portcheck.py" "$B/syn/$BLK_SYN/$BLK_TOP.v" "$d/out/$BLK_TOP.v" "$BLK_TOP"
}
blk_pnr() {
    local all="libs init floorplan place cts route outputs" from=${QC_PNR_FROM:-libs} to=${QC_PNR_TO:-outputs} s on=0
    for s in "$from" "$to"; do
        case " $all " in *" $s "*) ;; *) echo "BLK_FAIL pnr: unknown step '$s' (QC_PNR_FROM / QC_PNR_TO: $all)"; return 1 ;; esac
    done
    case "$all " in *"$to "*"$from "*) echo "BLK_FAIL pnr: QC_PNR_TO=$to is before QC_PNR_FROM=$from"; return 1 ;; esac
    for s in $all; do
        [ "$s" = "$from" ] && on=1; [ $on = 1 ] || continue
        if [ "$s" = outputs ]; then blk_out route || return 1
        elif [ "$s" = libs ]; then blk_libs || return 1
        else
            blk_unlabel "$s" || return 1
            if [ "$s" = init ]; then blk_inputs || return 1; fi
            if [ "$s" = floorplan ]; then blk_pins || return 1; fi
            qb_icc2 "$d" "$s" || return 1
        fi
        [ "$s" = "$to" ] && break
    done
    tail -n 40 "$d/summary.txt"
}
# A pnr step that writes a design label (init .. route) rewrites route, which every label of out/ (route, eco, eco2, ...)
# is built from, so out/ is no longer the layout of its label: the label of out/ and an unfinished one are dropped before
# the step (R99; [M] hunt on 44735f5: QC_PNR_TO=route kept out/label.txt = route over the old out/, and post / calibre
# signed off the old layout).  A pnr range that ends with outputs writes the label of out/ again.
blk_unlabel() {
    [ -e "$d/out/label.txt" ] || [ -e "$d/out/label.new" ] || return 0
    echo "BLK_LABEL pnr $1 rewrites the layout: label of out/ $(cat "$d/out/label.txt" 2> /dev/null || echo none), unfinished $(cat "$d/out/label.new" 2> /dev/null || echo none): dropped"
    rm -f "$d/out/label.txt" "$d/out/label.new"
}
# The inputs of the pnr step from outside the snapshot (R100 [M] hunt on a06c97: nothing recorded which netlist a run was
# built from): one summary.txt line "init inputs syn <tag> netlist <md5> sdc <md5> run_env <md5> [<key> <md5> ...]" before
# each init step: the DC inputs ($B/syn/$BLK_SYN: the netlist and DC SDC common/block_sdc.tcl reads, DC's run.env), then
# the block's own BLK_INPUTS (R101: the column's pin-reference abstract COL_REFLEF was recorded nowhere); common/regress.sh
# check compares the last line with the regression reference
blk_inputs() {
    local s=$B/syn/$BLK_SYN k f l="init inputs syn $BLK_SYN"
    for k in "netlist=$s/$BLK_TOP.v" "sdc=$s/$BLK_TOP.sdc" "run_env=$s/run.env" ${BLK_INPUTS:-}; do
        f=${k#*=}; [[ $k == [a-z]*=?* ]] || { echo "BLK_FAIL pnr init: input '$k' is not <key>=<file>"; return 1; }
        [ -f "$f" ] || { echo "BLK_FAIL pnr init: no input $f"; return 1; }
        l="$l ${k%%=*} $(md5sum < "$f" | cut -c1-32)"
    done
    mkdir -p "$d" && echo "$l" >> "$d/summary.txt" && echo "BLK_INPUTS $l"
}
# The floorplan pin DEF of the run, QB_PIN_DEF = <run>/pins.def (the block config's P(PIN_DEF)): written by the block's
# blk_pre_pnr right before each floorplan step, as <def>.part renamed into place (R99; before, $B/icc2/<blk>/pins*.def:
# one file per host that every pnr rewrote in place, so concurrent runs raced and a later floorplan re-run read another
# run's pins)
blk_pins() {
    declare -F blk_pre_pnr > /dev/null || { echo "BLK_FAIL pnr floorplan: the block has no blk_pre_pnr (pin DEF)"; return 1; }
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
    if [ "$s" = outputs ]; then { echo "$l outputs" > "$n" && QB_ICC2_LABEL=$l qb_icc2 "$d" outputs; } || return 1; fi
    { echo "$l fill" > "$n" && blk_portcheck && blk_fill_label "$l"; } || return 1
    echo "$l" > "$n.tmp" && mv -f "$n.tmp" "$d/out/label.txt" && rm -f "$n" && echo "BLK_LABEL $l is the label of out/"
}
blk_pending() {   # finishes the unfinished label of out/ (out/label.new), if there is one
    local l s
    [ -f "$d/out/label.new" ] || return 0
    read -r l s < "$d/out/label.new"
    case $s in outputs|fill) ;; *) echo "BLK_FAIL out/label.new '$l $s' is not '<label> outputs|fill'"; return 1 ;; esac
    echo "BLK_LABEL finishing the unfinished label $l of out/ from its $s stage"
    blk_out "$l" "$s"
}
# fill step: the unfinished label of out/ if there is one, else the label of out/ again (portcheck, fill, extract)
blk_fill() {
    local l
    if [ -f "$d/out/label.new" ]; then blk_pending; else l=$(blk_label) && blk_out "$l" fill; fi
}
# Calibre dummy metal + dummy OD / PO of out/<top>.gds; metal -> DEF FILLS -> fill-aware SPEFs of every sign-off corner
# (flow/icc2/extract.tcl on label $1, the label out/ was written from)
blk_fill_label() {
    local l=$1 o=$d/calibre C=$QBF/signoff/calibre w; mkdir -p "$o"
    # chip window of both fill decks = the DEF DIEAREA (DIEAREA as a rectangle or, as ICC2 writes it, a polygon: its
    # bounding box) -> calibre/die_window.sed.  Metal too since R99 (signoff/calibre/fill_blk.sed ChipWindowUsed; [M] rgr
    # rg44735f5a: without a window the metal fill took the drawn extent, y 4.76 .. 124.04 of the 130-um die, and stopped
    # 7.3 / 8.5 um short of the bottom / top edge, the OD / PO fill 0.6 um)
    w=$(zcat "$d/out/$BLK_TOP.def.gz" | awk '$1 == "UNITS" { u = $4 } $1 == "DIEAREA" { n = 0
        for (i = 2; i <= NF; i++) if ($i ~ /^-?[0-9.]+$/) v[n++] = $i / u
        x0 = x1 = v[0]; y0 = y1 = v[1]
        for (i = 2; i + 1 < n; i += 2) { x0 = v[i] < x0 ? v[i] : x0; x1 = v[i] > x1 ? v[i] : x1; y0 = v[i+1] < y0 ? v[i+1] : y0; y1 = v[i+1] > y1 ? v[i+1] : y1 }
        printf "%s %s %s %s", x0, y0, x1, y1; exit }')
    set -- $w; [ $# = 4 ] || { echo "BLK_FAIL no DIEAREA in out/$BLK_TOP.def.gz"; return 1; }
    printf 's#^VARIABLE xLB .*#VARIABLE xLB %s#\ns#^VARIABLE yLB .*#VARIABLE yLB %s#\ns#^VARIABLE xRT .*#VARIABLE xRT %s#\ns#^VARIABLE yRT .*#VARIABLE yRT %s#\n' "$@" > "$o/die_window.sed"
    QB55_FILL_SED="$BLK_FILL_SED -f $o/die_window.sed" bash "$C/cal.sh" fill "$d/out/$BLK_TOP.gds" "$BLK_TOP" "$o/fill" > "$o/fill.log" 2>&1 \
        || { cat "$o/fill.log"; return 1; }
    grep -v '^CAL55_fill' "$o/fill.log"
    # dummy OD / PO (R77) on the metal-filled GDS (signoff/calibre/odpo_blk.sed) -> odpo/<top>_fill.gds: the GDS of
    # Calibre LVS / DRC / antenna (calibre step).  FEOL dummies only: no effect on the metal SPEFs.
    QB77_ODPO_SED="$BLK_ODPO_SED -f $o/die_window.sed" bash "$C/cal.sh" odpo "$o/fill/${BLK_TOP}_fill.gds" "$BLK_TOP" "$o/odpo" > "$o/odpo.log" 2>&1 \
        || { cat "$o/odpo.log"; return 1; }
    cat "$o/odpo.log"
    ( . "$C/kl.sh"; kl_run "$C/fill_def.py" -rd gds="$o/fill/DM.gds" -rd design="$BLK_TOP" -rd out="$d/out/${BLK_TOP}_fill.def" ) || return 1
    QB_ICC2_LABEL=$l qb_icc2 "$d" extract || return 1
    grep '^extract' "$d/summary.txt" | tail -n 4
}
# ICC2 label of the ECO round that starts from label $1 / number of rounds that built label $1
blk_eco_label() { case $1 in route) echo eco ;; eco) echo eco2 ;; eco[1-9]*) echo "eco$(( ${1#eco} + 1 ))" ;; *) return 1 ;; esac; }
blk_eco_index() { case $1 in route) echo 0 ;; eco) echo 1 ;; eco[1-9]*) echo "${1#eco}" ;; *) return 1 ;; esac; }
blk_eco() {
    local max=${QC_ECO_ROUNDS:-4} e=$d/out/eco h k from to a tot prev r f cs n
    cs=$(qb_corners) || return 1   # (assigned first: a command substitution in an assignment prefix hides the status)
    h=$e/rounds.txt; mkdir -p "$e"
    # The history decides (R92 review; before, a second eco step forgot the stop and the previous total): a recorded stop
    # ends every later eco step too, unless it is overridden explicitly, which the history then says.
    case $(tail -n 1 "$h" 2> /dev/null) in *": FAIL "*)
        if [ "${QC_ECO_OVERRIDE_STOP:-}" != 1 ]; then
            echo "BLK_FAIL eco: the loop of this run has stopped ($h):"; tail -n 1 "$h"
            echo "  QC_ECO_OVERRIDE_STOP=1 continues from label $(cat "$d/out/label.txt" 2> /dev/null) and is logged there"; return 1
        fi
        echo "ECO override $(date +%F_%T) of the stop above (QC_ECO_OVERRIDE_STOP=1)" | tee -a "$h" ;;
    esac
    # an unfinished label of out/ (a round that failed after its ICC2 eco) is finished before any PrimeTime round
    blk_pending || { echo "ECO $(date +%F_%T) the unfinished label of out/ ($(cat "$d/out/label.new")) failed again" | tee -a "$h"; return 1; }
    while :; do
        from=$(blk_label) || return 1
        to=$(blk_eco_label "$from") || { echo "BLK_FAIL eco: no ECO label after '$from' (out/label.txt)"; return 1; }
        k=$(( $(blk_eco_index "$from") + 1 ))
        # pre-fix total of the round that built label $from (none: route, or a stop overridden since)
        prev=$(awk -v l="$from" '$2 == "override" { p = "" } $9 == "change" && $13 == l { p = $8; sub(":", "", p) } END { print p }' "$h" 2> /dev/null)
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
              QB_ECO_BLOCK=$BLK_TOP/$from qb_pt pt_eco.log pt_shell -multi_scenario -f "$QBF/signoff/pt/drv_eco.tcl" ); r=$?
        rm -f "$e"/work/.eco_ndm_*   # (the DMSA workers' NDM copies, ~0.42 GB each: disk, R71; their logs stay)
        for f in "$d/pt_eco.log" "$e"/*.txt "$e"/*.tcl "$e"/*.log; do [ -f "$f" ] && [ "$f" != "$h" ] && cp "$f" "$a/"; done
        [ $r = 0 ] || return 1
        cat "$e/eco_summary.txt"
        tot=$(awk '$1 == "prefix_total" { print $2; exit }' "$e/eco_summary.txt")
        case $tot in ''|*[!0-9]*) echo "BLK_FAIL eco: no prefix_total in out/eco/eco_summary.txt"; return 1 ;; esac
        # opt-in QC_ECO_PT_ONLY=1: this round's PrimeTime half only (a check of the PT side, e.g. on a copy of a run): the
        # record and a history line, no verdict on the loop, nothing applied
        if [ "${QC_ECO_PT_ONLY:-}" = 1 ]; then
            echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: PrimeTime only (QC_ECO_PT_ONLY=1), change list not applied" | tee -a "$h"
            return 0
        fi
        if [ "$tot" = 0 ]; then
            echo "ECO round $k $(date +%F_%T) label $from prefix_total 0: converged" | tee -a "$h"
            grep '^eco' "$d/summary.txt" | tail -n 20; return 0
        fi
        if [ "$k" -gt "$max" ]; then
            echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL not converged after $max rounds" | tee -a "$h"; return 1
        fi
        if [ -n "$prev" ] && [ "$tot" -ge "$prev" ]; then
            echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL not smaller than the previous round's $prev" | tee -a "$h"
            # the change list of this round is not applied: no label $to; marked in the record, gone from out/eco
            for f in pt_eco.tcl pt_eco_cells.txt; do [ -f "$a/$f" ] && mv "$a/$f" "$a/${f%.*}.not_applied.${f##*.}"; rm -f "$e/$f"; done
            return 1
        fi
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: change list -> label $to" | tee -a "$h"
        # ICC2: the change list on label $from -> $to (name / load / legality gates, ECO route, route gate), then out/ for
        # label $to (blk_out: outputs, portcheck, fill, extract; only then is $to the label of out/)
        QB_ECO_FROM=$from QB_ECO_TO=$to qb_icc2 "$d" eco; r=$?; cp "$d/eco.log" "$a/"
        [ $r = 0 ] && blk_out "$to" \
            || { echo "ECO round $k $(date +%F_%T) label $from: failed after the change list (label of out/: $(cat "$d/out/label.txt" 2> /dev/null || echo none), unfinished: $(cat "$d/out/label.new" 2> /dev/null || echo none))" | tee -a "$h"; return 1; }
    done
}
# On the filled GDS of the fill step (metal: the one the SPEFs saw; + OD / PO): LVS source, Calibre LVS, DRC (block deck),
# antenna -> <run>/calibre.  All three run; the step fails on any cal.sh exit status (LVS not CORRECT, an LVS ERC result
# or a NOT EXECUTED ERC check signoff/calibre/erc_allow.txt does not allow, any DRC / antenna result: signoff/calibre/cal.sh).
blk_calibre() {
    local o=$d/calibre C=$QBF/signoff/calibre g r=0; g=$o/odpo/${BLK_TOP}_fill.gds
    blk_label > /dev/null || return 1
    [ "$g" -nt "$d/out/$BLK_TOP.gds" ] || { echo "BLK_FAIL $g missing or older than out/$BLK_TOP.gds (run.sh fill)"; return 1; }
    bash "$C/lvs_src.sh" "$d/out/${BLK_TOP}_pg.v" "$o/${BLK}_src.spi" > "$o/src.log" 2>&1; r=$?; tail -n 3 "$o/src.log"; [ $r = 0 ] || return 1
    QB36_LVS_SED=$BLK_LVS_SED bash "$C/cal.sh" lvs "$g" "$BLK_TOP" "$o/${BLK}_src.spi" "$o/lvs" > "$o/lvs.log" 2>&1 || r=1
    QB36_DRC_SED=$BLK_DRC_SED bash "$C/cal.sh" drc "$g" "$BLK_TOP" "$o/drcb" > "$o/drcb.log" 2>&1 || r=1
    bash "$C/cal.sh" ant "$g" "$BLK_TOP" "$o/ant" > "$o/ant.log" 2>&1 || r=1
    cat "$o/lvs.log" "$o/drcb.log" "$o/ant.log"; return $r
}
# PrimeTime in every sign-off corner on the ICC2 netlist + SPEF (fails on any setup / hold / DRV / noise / min pulse width
# / min period violator, common/env.sh qb_pt), then the ETMs of every corner (R71; fails on MEXT-6 / MEXT-81 / MEXT-97)
blk_post() {
    blk_label > /dev/null || return 1
    ( blk_pt_env || exit 1
      cs=$(qb_corners) || exit 1; r=0
      for c in $cs; do   # every corner is reported before a failure stops the step (R67)
          QC_CORNER=$c qb_pt "pt_blk_$c.log" pt_shell -f "$BLK_PT" || r=1
          cat "pt_blk_$c.txt"
      done
      [ $r = 0 ] || exit 1
      for c in $cs; do
          QC_CORNER=$c qb_pt "etm_$c.log" pt_shell -f "$QBF/signoff/etm/etm.tcl" || r=1
          ! grep -m 3 'MEXT-6)\|MEXT-81\|MEXT-97' "etm_$c.log" || { echo "ETM $c: table limit / driving cell / feedthrough warnings"; r=1; }
          echo "ETM $c $(ls out/etm/ 2> /dev/null | grep -c '_lib.db$') dbs, $(grep -c 'RC-011' "etm_$c.log") RC-011 lines"
      done; exit $r )
}
# Views for the chip top: ICC2 abstract LEF with port antenna data + antenna / abutment / PG pin gates (flow/icc2/
# abstract.tcl, on the label of out/, which it records in summary.txt for signoff/verdict.py) -> out/<top>.lef; ETM
# gate (signoff/etm/etmcheck.py: against the netlist reference of the same session) of the post step's ETMs
blk_views() {
    local c cs own
    cs=$(qb_corners) || return 1
    own=$(blk_label) || return 1
    # (R99; was a warning since R92) the abstract is of the layout of out/ only: an inherited QB_ICC2_LABEL naming
    # another label fails
    if [ -n "${QB_ICC2_LABEL:-}" ] && [ "$QB_ICC2_LABEL" != "$own" ]; then
        echo "BLK_FAIL views: QB_ICC2_LABEL=$QB_ICC2_LABEL is not the label of out/ ($own)"; return 1
    fi
    echo "BLK_VIEWS abstract of label $own = the label of out/"
    QB_ICC2_LABEL=$own QB_PY=$PY qb_icc2 "$d" abstract || return 1
    grep '^abstract' "$d/summary.txt" | tail -n 3
    for c in $cs; do "$PY" -I "$QBF/signoff/etm/etmcheck.py" "$d/out/etm/${BLK_TOP}_$c.lib" || return 1; done
}
# The machine verdict of the run dir (signoff/verdict.sh: every sign-off gate re-read from the run's files; one GATE line
# per gate, last line SIGNOFF <top> PASS|FAIL): its exit status is the step's
blk_signoff() {
    local v=$QBF/signoff/verdict.sh
    [ -f "$v" ] || { echo "BLK_FAIL signoff: $v missing"; return 1; }
    bash "$v" ${BLK_GATES:+-g "$BLK_GATES"} "$d" || return 1
}
