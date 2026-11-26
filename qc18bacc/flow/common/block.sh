# Shared driver of an ICC2 hard block (R92).  A block's run.sh sources common/env.sh and this file, sets the variables
# below and ends with  blk_main "$@"   (run.sh <step> <tag>; run dir $B/icc2/$BLK/<tag>; exit status non-zero when a
# tool or a gate of the step failed):
#   BLK block name   BLK_TOP top cell   BLK_SYN DC netlist tag ($B/syn/<tag>)   BLK_PERIOD clock period (ns) of P&R and
#   sign-off   BLK_CFG ICC2 block config (flow/icc2 QB_ICC2_CFG; export what it reads from the environment yourself)
#   BLK_PT PrimeTime sign-off script of one corner QC_CORNER (writes <run>/pt_blk_<corner>.txt; must return after its
#   design setup when ::QB_PT_SETUP_ONLY exists)   blk_pre_pnr optional function run before pnr's ICC2 steps (pin DEF)
#   BLK_FILL_SED BLK_ODPO_SED BLK_LVS_SED BLK_DRC_SED Calibre deck seds as sed arguments ("-f <file>" ...)
# Steps:  pnr      ICC2 libs init floorplan place cts route outputs, then portcheck + fill; QC_PNR_FROM / QC_PNR_TO select
#                  a range, an unknown step name fails
#         eco      sign-off ECO loop, at most QC_ECO_ROUNDS (4) rounds: PrimeTime DMSA -> ICC2 eco -> outputs -> portcheck
#                  -> fill; ends when a round's pre-fix state is clean in every corner at zero margin; fails if it never
#                  is, or if the pre-fix violation total does not shrink.  Hold is fixed to QC_ECO_HOLD_MARGIN (env.sh)
#         fill     Calibre dummy metal + OD / PO, fill-aware SPEFs      calibre  LVS, DRC, antenna (fails on cal.sh's status)
#         post     PrimeTime sign-off + ETMs in every corner   views  abstract LEF + ETM scan   signoff  signoff/verdict.sh
#
# Details.  rundir <tag> (a further step) prints the run dir (common/queue.sh).  The label of out/ is out/label.txt
# (flow/icc2/outputs.tcl): route, then eco, eco2, ... (one ICC2 label per ECO round, so every round's layout stays in the
# design library).  ECO round files: out/eco/<label>/ (PrimeTime log, eco_summary.txt, change list + new-cell record,
# unfixable reasons, ICC2 log), out/eco/rounds.txt (one line per round).
# Why a loop (R92, PI decision; r91b [M]): one zero-margin ECO pass predicted 0 violators in 9 corners and its own ECO
# route left 2 hold endpoints at -0.04 / -0.09 ps and one net 1.7 ps over max_transition, all on nets the ECO had not
# touched (264 hold endpoints within 5 ps of zero at wcl).  Convergence is judged by PrimeTime at the sign-off criterion
# (signoff/pt/drv_eco.tcl prefix_total: setup + hold + max_transition + max_capacitance + noise, zero margin), never at
# the fix margin; a total that does not shrink is a bug to diagnose, so the step stops there.
blk_main() {
    local step=${1:?step} tag=${2:?tag}; d=$B/icc2/$BLK/$tag
    export QB_SYN=$BLK_SYN QB_PNR_PERIOD=$BLK_PERIOD QB_ICC2_CFG=$BLK_CFG
    case $step in
    rundir) echo "$d"; return 0 ;;
    pnr|eco|fill|calibre|post|views|signoff) ;;
    *) sed '/^#$/,$d' "${BASH_SOURCE[0]}"; echo "BLK_FAIL $BLK: unknown step '$step'"; return 1 ;;
    esac
    echo "BLK_STEP $BLK $step $tag $(date +%T)"
    "blk_$step" || { echo "BLK_FAIL $BLK $step $tag $(date +%T)"; return 1; }
    echo "BLK_DONE $BLK $step $tag $(date +%T)"
}
blk_pt_env() {   # PrimeTime environment of $BLK_PT, set in the subshell of the caller
    qb_kit; set -a; . "$B/syn/$BLK_SYN/run.env"; set +a
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
    if declare -F blk_pre_pnr > /dev/null; then blk_pre_pnr || return 1; fi
    for s in $all; do
        [ "$s" = "$from" ] && on=1; [ $on = 1 ] || continue
        qb_icc2 "$d" "$s" "$([ "$s" = libs ] && echo icc2_lm_shell)" || return 1
        if [ "$s" = outputs ]; then blk_portcheck && blk_fill || return 1; fi
        [ "$s" = "$to" ] && break
    done
    tail -n 40 "$d/summary.txt"
}
# Calibre dummy metal + dummy OD / PO of out/<top>.gds; metal -> DEF FILLS -> fill-aware SPEFs of every sign-off corner
# (flow/icc2/extract.tcl, the label of out/)
blk_fill() {
    local o=$d/calibre C=$QBF/signoff/calibre w; mkdir -p "$o"
    QB55_FILL_SED=$BLK_FILL_SED bash "$C/cal.sh" fill "$d/out/$BLK_TOP.gds" "$BLK_TOP" "$o/fill" > "$o/fill.log" 2>&1 \
        || { cat "$o/fill.log"; return 1; }
    grep -v '^CAL55_fill' "$o/fill.log"
    # dummy OD / PO (R77) on the metal-filled GDS, chip window = the DEF DIEAREA (signoff/calibre/odpo_blk.sed) ->
    # odpo/<top>_fill.gds: the GDS of Calibre LVS / DRC / antenna (calibre step).  FEOL dummies only: no effect on the
    # metal SPEFs.  (DIEAREA as a rectangle or, as ICC2 writes it, a polygon: its bounding box)
    w=$(zcat "$d/out/$BLK_TOP.def.gz" | awk '$1 == "UNITS" { u = $4 } $1 == "DIEAREA" { n = 0
        for (i = 2; i <= NF; i++) if ($i ~ /^-?[0-9.]+$/) v[n++] = $i / u
        x0 = x1 = v[0]; y0 = y1 = v[1]
        for (i = 2; i + 1 < n; i += 2) { x0 = v[i] < x0 ? v[i] : x0; x1 = v[i] > x1 ? v[i] : x1; y0 = v[i+1] < y0 ? v[i+1] : y0; y1 = v[i+1] > y1 ? v[i+1] : y1 }
        printf "%s %s %s %s", x0, y0, x1, y1; exit }')
    set -- $w; [ $# = 4 ] || { echo "BLK_FAIL no DIEAREA in out/$BLK_TOP.def.gz"; return 1; }
    printf 's#^VARIABLE xLB .*#VARIABLE xLB %s#\ns#^VARIABLE yLB .*#VARIABLE yLB %s#\ns#^VARIABLE xRT .*#VARIABLE xRT %s#\ns#^VARIABLE yRT .*#VARIABLE yRT %s#\n' "$@" > "$o/odpo_window.sed"
    QB77_ODPO_SED="$BLK_ODPO_SED -f $o/odpo_window.sed" bash "$C/cal.sh" odpo "$o/fill/${BLK_TOP}_fill.gds" "$BLK_TOP" "$o/odpo" > "$o/odpo.log" 2>&1 \
        || { cat "$o/odpo.log"; return 1; }
    cat "$o/odpo.log"
    ( . "$C/kl.sh"; kl_run "$C/fill_def.py" -rd gds="$o/fill/DM.gds" -rd design="$BLK_TOP" -rd out="$d/out/${BLK_TOP}_fill.def" ) || return 1
    QB_ICC2_LABEL=$(cat "$d/out/label.txt") qb_icc2 "$d" extract || return 1
    grep '^extract' "$d/summary.txt" | tail -n 4
}
# ICC2 label of the ECO round that starts from label $1
blk_eco_label() { case $1 in route) echo eco ;; eco) echo eco2 ;; eco[1-9]*) echo "eco$(( ${1#eco} + 1 ))" ;; *) return 1 ;; esac; }
blk_eco() {
    local max=${QC_ECO_ROUNDS:-4} e=$d/out/eco k from to a tot prev= r f cs
    cs=$(qb_corners) || return 1   # (assigned first: a command substitution in an assignment prefix hides the status)
    for (( k = 1; k <= max + 1; k++ )); do
        from=$(cat "$d/out/label.txt" 2> /dev/null || echo route)
        to=$(blk_eco_label "$from") || { echo "BLK_FAIL eco: no ECO label after '$from' (out/label.txt)"; return 1; }
        a=$e/$to; mkdir -p "$a"
        # PrimeTime DMSA on the outputs of label $from: pre-fix state of every corner at the sign-off criterion, then the
        # change list, unless that state is clean (converged) or this is the check after the last round (QB_ECO_CHECK)
        ( blk_pt_env || exit 1
          QB_ECO_CHECK=$(( k > max )) QB_PT_SCRIPT=$BLK_PT QB_ECO_CORNERS=$cs QB_ECO_NLIB=$d/$BLK_TOP.nlib \
              QB_ECO_BLOCK=$BLK_TOP/$from qb_pt pt_eco.log pt_shell -multi_scenario -f "$QBF/signoff/pt/drv_eco.tcl" ); r=$?
        rm -f "$e"/work/.eco_ndm_*   # (the DMSA workers' NDM copies, ~0.42 GB each: disk, R71; their logs stay)
        # the round's record: PrimeTime log, state summary, change list + new-cell record, unfixable reasons, physical logs
        for f in "$d/pt_eco.log" "$e"/*.txt "$e"/*.tcl "$e"/*.log; do [ -f "$f" ] && cp "$f" "$a/"; done
        [ $r = 0 ] || return 1
        cat "$e/eco_summary.txt"
        tot=$(awk '$1 == "prefix_total" { print $2; exit }' "$e/eco_summary.txt")
        case $tot in ''|*[!0-9]*) echo "BLK_FAIL eco: no prefix_total in out/eco/eco_summary.txt"; return 1 ;; esac
        if [ "$tot" = 0 ]; then
            echo "ECO round $k $(date +%F_%T) label $from prefix_total 0: converged" | tee -a "$e/rounds.txt"
            grep '^eco' "$d/summary.txt" | tail -n 20; return 0
        fi
        if [ "$k" -gt "$max" ]; then
            echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL not converged after $max rounds" | tee -a "$e/rounds.txt"; return 1
        fi
        if [ -n "$prev" ] && [ "$tot" -ge "$prev" ]; then
            echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: FAIL not smaller than the previous round's $prev" | tee -a "$e/rounds.txt"; return 1
        fi
        prev=$tot
        echo "ECO round $k $(date +%F_%T) label $from prefix_total $tot: change list -> label $to" | tee -a "$e/rounds.txt"
        # ICC2: the change list on label $from -> $to (name / load / legality gates, ECO route, route closure + gate)
        QB_ECO_FROM=$from QB_ECO_TO=$to qb_icc2 "$d" eco; r=$?; cp "$d/eco.log" "$a/"; [ $r = 0 ] || return 1
        QB_ICC2_LABEL=$to qb_icc2 "$d" outputs || return 1
        blk_portcheck && blk_fill || return 1
    done
}
# On the filled GDS of the fill step (metal: the one the SPEFs saw; + OD / PO): LVS source, Calibre LVS, DRC (block deck),
# antenna -> <run>/calibre.  All three run; the step fails on any cal.sh exit status (LVS not CORRECT, any DRC / antenna
# result: signoff/calibre/cal.sh).
blk_calibre() {
    local o=$d/calibre C=$QBF/signoff/calibre g r=0; g=$o/odpo/${BLK_TOP}_fill.gds
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
# abstract.tcl, label QB_ICC2_LABEL [the label of out/]) -> out/<top>.lef; ETM scan (etmcheck 3 ns) of the post step's ETMs
blk_views() {
    local c cs
    cs=$(qb_corners) || return 1
    QB_ICC2_LABEL=${QB_ICC2_LABEL:-$(cat "$d/out/label.txt" 2> /dev/null || echo route)} QB_PY=$PY qb_icc2 "$d" abstract || return 1
    grep '^abstract' "$d/summary.txt" | tail -n 3
    for c in $cs; do "$PY" -I "$QBF/signoff/etm/etmcheck.py" "$d/out/etm/${BLK_TOP}_$c.lib" 3.0 || return 1; done
}
# The machine verdict of the run dir (signoff/verdict.sh: every sign-off gate re-read from the run's files; one GATE line
# per gate, last line SIGNOFF <top> PASS|FAIL): its exit status is the step's
blk_signoff() {
    local v=$QBF/signoff/verdict.sh
    [ -f "$v" ] || { echo "BLK_FAIL signoff: $v missing"; return 1; }
    bash "$v" "$d" || return 1
}
