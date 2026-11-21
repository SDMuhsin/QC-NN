#!/usr/bin/env bash
# R35 (results/r35.md): first full-chip sign-off at one relaxed chip period.  On tau from the snapshot root
# (QC_BUILD as before); every step imports an existing flow script:
#   qc18bacc/impl/r35/run35.sh col <tag> <period>    column qb_col_blk = impl/r5d/run.sh pnr recipe (R5d netlist, r5d_C tiles)
#                                                    with impl/r35/col.cfg (r5b_blk pin positions, GRT M2-M3 0.6, antenna repair,
#                                                    DR <= QB_DR_ITER [64])
#   qc18bacc/impl/r35/run35.sh colfrom <tag> <period> column again from QB35_SRC's cts db (QB_IO_LAT = PT-measured L)
#   qc18bacc/impl/r35/run35.sh colpost <tag> <period> column SPEFs tt / ss / ff (QC_SPEF_UNESC 1), PT tt / ss + abstract + ETMs
#                                                    (impl/r5a/post.sh pt abs etm at <period>), LEF-rule antenna (impl/r29/antd29.tcl)
#   qc18bacc/impl/r35/run35.sh part r35_w -          chip DC netlist QB_SYN [r35_ptr] -> hub partition $B/<tag> (impl/r9b dump part ports sdc)
#   qc18bacc/impl/r35/run35.sh nl <part tag> -       top netlist (impl/r11/top_nl.py) -> $B/r35/top_r35.v (+ _bpins / _equiv / _actmap)
#   qc18bacc/impl/r35/run35.sh act <tag> <period>    act block = impl/r20/run.sh all (QB_SYN [r35_act], col pins $B/r35/col_act_pins.txt,
#                                                    s_q x0 QB13_SQX0 [64] = hub x 40 + 24, P&R / PT period, GRT M2-M3 0.6)
#   qc18bacc/impl/r35/run35.sh actabs <tag> <period> act abstracts (impl/r20/run.sh abs -> impl/r9a abs) of <tag>
#   qc18bacc/impl/r35/run35.sh abs <act run> <period> top views $B/r35/abs: hub ring LEF + ETMs (QB35_HUBABS [$B/r22_r34_A]),
#                                                    act: QB35_ACTABS dir with LEF + ETMs, else early view of <act run>'s floorplan
#                                                    (actlef.tcl + actlef.py) + budget liberty (impl/r11/blk_lib.py); column
#                                                    insfix ETMs (impl/r7b/etm_fix.py on QB35_COLLIB [$B/r5b_blk] *_ins.lib)
#   qc18bacc/impl/r35/run35.sh tfp <tag> <period>    top init + macro dump + fp14.py (QB14_HUBX 40, QB_NB [300]) + floorplan / pdn (impl/r35/top.cfg)
#   qc18bacc/impl/r35/run35.sh tpnr <tag> <period>   top place .. GRT (+ repair at GRT parasitics), db/grt.odb
#   qc18bacc/impl/r35/run35.sh tdr <tag> <period>    top detailed route (impl/r8/run.sh dr, QB_DR_ITER [64])
#   qc18bacc/impl/r35/run35.sh tpt <tag> <period>    chip PrimeTime tt / ss (impl/r5b/pt_chip.tcl, QC_SDC impl/r35/pt_top_sdc.tcl, top latency
#                                                    QB35_TOPL) with block ETM dbs QB35_{COL,HUB,ACT}DB dirs + the chip run.env macro dbs
#   qc18bacc/impl/r35/run35.sh hold <tag> -          opt-in post-route hold repair (hold35.tcl: repair_timing -hold on the routed SPEF,
#                                                    rip + GRT + DR of the touched nets, finish) then SPEFs (def2spef, QC_SPEF_ORFIX 1)
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$(cd "$here/.." && pwd); root=$(cd "$I/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
step=${1:?step}; tag=${2:?tag}; per=${3:-5.0}
echo "R35_STEP $step $tag $per $(date +%T)"
case $step in
col) mkdir -p "$B/r35"; "$PY" -I "$here/colpins.py" "$B/r5b_blk/qb_col_blk_ring.lef" "$B/r35/colpins.tcl" || exit 1
     cd "$root" && QC_PNR_THREADS=${QC_PNR_THREADS:-15} QB_CFG=../r35/col.cfg QB_SYN=${QB35_COLSYN:-qb_col_blk_r5d_s20_tt_p1.65_topo} \
       QB_BRG=2 QB_PM=seed QB_PNR_PERIOD=$per QB_REPIN=0 QB_RT_LOOPS=0 QB_INC_POST=1 QB_GR_ADJ=0.15 QB_W=380 QB_INC_DENS=0.80 \
       QB_DR_ITER=${QB_DR_ITER:-64} QB_TILE_DIR=${QB35_TILES:-$B/r5d_Ctiles} QB15_GADJ_L=${QB15_GADJ_L-"M2-M3 0.6"} \
       QB35_COLPINS=$B/r35/colpins.tcl QB_IO_LAT=${QB_IO_LAT:-0.85} "$I/pnr/run.sh" pnr "$tag" ;;
colfrom) # col <tag> again from <src>'s cts db (QB35_SRC), e.g. with the PT-measured insertion delay QB_IO_LAT
     s=$B/pnr/${QB35_SRC:?src}; d=$B/pnr/$tag; mkdir -p "$d/db" "$d/rpt"; cp -r "$s/rc" "$d/"
     for f in init floorplan pdn place cts; do cp "$s/db/$f.odb" "$s/db/$f.sdc" "$d/db/"; done
     QC_PNR_FROM=cts "$0" col "$tag" "$per" ;;
colpost) cd "$root" && QC_SPEF_UNESC=1 QB_SPEF_CORNERS="tt ss ff" "$I/pnr/run.sh" spef "$tag"
     QB_PT_PERIOD=$per "$I/r5a/post.sh" "$tag" "pt abs etm"
     R29_DB=${R29_DB:-route} R29_TAG=dr "$I/r29/or29.sh" "$tag" "$I/r29/antd29.tcl" r29_antd.log
     grep -hi "R29_ANTD\|found\|violat" "$B/pnr/$tag/r29_antd.log" | tail -4 ;;
part) export QB_SYN=${QB_SYN:-r35_ptr} QB9_W=$B/$tag
     for s in dump part ports sdc; do echo "== $s $(date +%T)"; "$I/r10b/run.sh" $s || { echo R35_PART_FAIL $s; exit 1; }; done ;;
nl)  mkdir -p "$B/r35"; cd "$B/r35" && "$PY" -I "$I/r11/top_nl.py" "$B/$tag/qb_chip_r9b_c.v" top_r35 | tail -20 ;;
act) # impl/r20/run.sh all, step by step (QB35_ACT_STEPS [p s c post]): <tag>_p pnr to CTS, <tag>_s post-CTS, <tag>_c route, post
     cd "$root" && export QB_SYN=${QB_SYN:-r35_act} QB7_COLPINS=${QB7_COLPINS:-$B/r35/col_act_pins.txt} QB13_SQX0=${QB13_SQX0:-64} \
       QB_IO_LAT=${QB_IO_LAT:-0.77} QB15_GADJ_L=${QB15_GADJ_L-"M2-M3 0.6"} QC_SPEF_ORFIX=1 QC_SPEF_UNESC=1
     for st in ${QB35_ACT_STEPS:-p s c post}; do echo "R35_ACT $st $(date +%T)"; case $st in
       p) QC_PNR_TO=cts QB_PNR_PERIOD=$per "$I/r20/run.sh" pnr ${tag}_p || exit 1 ;;
       s) QB_PNR_PERIOD_RT=$per QB16_PEN=${QB16_PEN:-0.01} QB16_OVF=${QB16_OVF:-0.05} QB16_S1INF=${QB16_S1INF:-1} "$I/r20/run.sh" postcts ${tag}_p ${tag}_s || exit 1 ;;
       c) QB9_GR_ADJ=${QB9_GR_ADJ:-0.25} QB9_GR_ITER=${QB9_GR_ITER:-10} QB9_ANT=${QB9_ANT:-1} QB_DR_ITER=${QB_DR_ITER:-64} \
            QC_PNR_THREADS=${QC_PNR_THREADS:-14} "$I/r20/run.sh" rt ${tag}_s ${tag}_c ;;
       post) QB_PT_PERIOD=$per "$I/r20/run.sh" post ${tag}_c ;;
     esac; done ;;
actabs) cd "$root" && QB_SYN=${QB_SYN:-r35_act} QB7_COLPINS=${QB7_COLPINS:-$B/r35/col_act_pins.txt} QB_PT_PERIOD=$per "$I/r20/run.sh" abs "$tag" ;;
abs) A=$B/r35/abs; mkdir -p "$A"; H=${QB35_HUBABS:-$B/r22_r34_A}
     ln -sf "$H/qb_hub_ring.lef" "$A/qb_hub.lef"; for c in tt ss ff; do ln -sf "$H/qb_hub_$c.lib" "$A/"; ln -sf "$H/qb_hub_${c}_lib.db" "$A/"; done
     if [ -n "${QB35_ACTKEEP:-}" ]; then echo "act views kept: $(ls "$A"/qb_act2_blk* | tr '\n' ' ')"
     elif [ -n "${QB35_ACTABS:-}" ]; then
       ln -sf "$QB35_ACTABS/qb_act2_blk_ring.lef" "$A/qb_act2_blk.lef"; for c in tt ss ff; do ln -sf "$QB35_ACTABS/qb_act2_blk_$c.lib" "$A/"; ln -sf "$QB35_ACTABS/qb_act2_blk_${c}_lib.db" "$A/"; done
     else
       ( . "$root/flow/tsmc65/common/tool.sh"; QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY
         cd "$B/pnr/$tag" && QC_FLOW=$FLOW QC_PNR_OUT=$B/pnr/$tag QB35_AOUT=$A/act_early.lef "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" -no_init -no_splash -exit "$here/actlef.tcl" > "$A/actlef.out" 2>&1 < /dev/null )
       "$PY" -I "$here/actlef.py" "$A/act_early.lef" "$A/qb_act2_blk.lef" ${QB35_ACTWH:-900 1970} || exit 1
       ( cd "$A" && rm -f qb_act2_blk_*.lib && "$PY" -I "$I/r11/blk_lib.py" "$per" qb_act2_blk.lef - act qb_act2_blk ) || exit 1
     fi
     L=${QB35_COLLIB:-$B/r5b_blk}; for c in tt ss ff; do "$PY" -I "$I/r7b/etm_fix.py" "$L/qb_col_blk_${c}_ins.lib" "$A/qb_col_blk_${c}_insfix.lib" | grep -c ETM_FIX; done
     ls -la "$A" ;;
tfp|tpnr|tdr)
     . "$root/flow/tsmc65/common/tool.sh"; QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY
     export QB_SYN=${QB_SYN:-r35_ptr} QB11_PER=$per QB11_ABS=${QB11_ABS:-$B/r35/abs} QB14_HUBX=${QB14_HUBX:-40} QB_NB=${QB_NB:-300}
     export QB_PDN_BLKX=${QB_PDN_BLKX-"qb_hub qb_act2_blk"}
     export QB_POSTCTS=${QB_POSTCTS:-1} QB15_GADJ_L=${QB15_GADJ_L-"M2-M3 0.6"} QC_PNR_THREADS=${QC_PNR_THREADS:-16}
     cfg=$here/top.cfg; d=$B/pnr/$tag
     case $step in
     tfp) QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag" || exit 1
          ( cd "$d" && QB_RUN=$d "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" -no_init -no_splash -exit "$I/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
          "$PY" -I "$I/r14/fp14.py" "$d/macros.txt" "$QB11_ABS" "$d/mplace.tcl" || exit 1
          QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag" ;;
     tpnr) QB_GRT_STOP=1 QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag" ;;
     tdr) QB_DR_ITER=${QB_DR_ITER:-64} QB8_DR_THREADS=${QB8_DR_THREADS:-16} "$I/r8/run.sh" dr "$tag" ;;
     esac ;;
tpt) d=$B/pnr/$tag
     for c in ${QB35_PTC:-tt ss}; do
     ( . "$root/flow/tsmc65/common/tool.sh"; cd "$d" && . ./kit.env; set -a; . "$B/syn/${QB_SYN:-r35_ptr}/run.env"; set +a
       C=$(echo $c | tr a-z A-Z); v=QC_EXTRA_DB_$C; m=""
       for f in ${!v}; do case $f in *qb_col_blk*) ;; *) m="$m $f" ;; esac; done
       export QC_EXTRA_DB_$C="$m ${QB35_COLDB:?}/qb_col_blk_${c}_lib.db ${QB35_HUBDB:?}/qb_hub_${c}_lib.db ${QB35_ACTDB:?}/qb_act2_blk_${c}_lib.db"
       export QC_SDC=$here/pt_top_sdc.tcl QC_PERIOD=$per QB35_TOPL=${QB35_TOPL:-0}
       QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c qc_tool "pt_chip_$c.log" pt_shell -f "$I/r5b/pt_chip.tcl"
       echo "PT_CHIP $c errors $(grep -c '^Error' pt_chip_$c.log)"; cat "pt_chip_$c.txt" ) &
     done; wait ;;
hold) d=$B/pnr/$tag
     ( . "$root/flow/tsmc65/common/tool.sh"; cd "$d" && . ./kit.env
       QC_SPEF_ORFIX=1 "$PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/tt.txt" "out/${TOP}_tt_or.spef" > def2spef_tt_or.log 2>&1 ) || exit 1
     QB35_SPEF=${QB35_SPEF:-$d/out/$(. "$d/kit.env"; echo $TOP)_tt_or.spef} "$I/r29/or29.sh" "$tag" "$here/hold35.tcl" r35_hold.log
     grep -h "R35_HOLD" "$d/r35_hold.log" | grep -v "^\[" ; grep -q "R35_HOLD saved" "$d/r35_hold.log" || exit 0
     ( . "$root/flow/tsmc65/common/tool.sh"; cd "$d" && . ./kit.env
       for c in $CORNERS; do
         QC_SPEF_ORFIX=1 "$PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_$c.spef" > "def2spef_$c.log" 2>&1 || echo "def2spef $c failed"
         QC_SPEF_UNESC=${QC_SPEF_UNESC:-1} "$PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" --escape-divider >> "def2spef_$c.log" 2>&1 || echo "def2spef $c (pt) failed"
       done ) ;;
*) sed -n '2,25p' "$0"; exit 1 ;;
esac
echo "R35_DONE $step $tag $(date +%T)"
