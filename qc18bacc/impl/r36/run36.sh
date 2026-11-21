#!/usr/bin/env bash
# R36 (results/r36.md): chip top level with the opt-in fixes of the R35a pre-mortem (top items 2 3 5 6 7 8 10).
# On tau from the snapshot root (QC_BUILD as before).  Every step imports impl/r35 / r5b / r7b / pnr scripts:
#   qc18bacc/impl/r36/run36.sh abs <name> -      top views $B/r36/<name>: ring LEF (impl/r5b/lef_ring.py) of the FINAL
#                                                block abstracts (exact M7-M9, PG pins, ANTENNA* if the LEF has them):
#                                                QB36_{COL,HUB,ACT}LEF; ETMs QB36_{COL,HUB,ACT}ETM dirs (<blk>_<c>.lib + _lib.db);
#                                                column OR copy = etm_ins.py (QB36_COLLAT_<C> "max min") + etm_fix.py.
#                                                Unset inputs fall back to the R35 views in $B/r35/abs.
#   qc18bacc/impl/r36/run36.sh tfp|tpnr <tag> <period>   = impl/r35/run35.sh tfp / tpnr with impl/r36/top.cfg and
#                                                QB11_ABS [$B/r36/abs], QB35_GRTHOLD [0] (bug 5), block insertion QB11_INS /
#                                                QB14_HINS / QB14_AINS (bug 7, defaults = R35 PT-measured tt), QB_NB [800]
#   qc18bacc/impl/r36/run36.sh tdr <tag> <period>  impl/r8/run.sh dr, then SPEF tt + ss with QC_SPEF_UNESC 1 (bug 6)
#   qc18bacc/impl/r36/run36.sh pgchk <tag> <db>    top PDN vs block LEFs (pgdump.tcl + pgovl.py), PG pins per block
#   qc18bacc/impl/r36/run36.sh tpt <tag> <period>  impl/r35/run35.sh tpt with the views' dbs (QB35_TOPL = QB36_TOPL)
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$(cd "$here/.." && pwd); root=$(cd "$I/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
step=${1:?step}; tag=${2:?tag}; per=${3:-6.5}
echo "R36_STEP $step $tag $per $(date +%T)"
export QB11_ABS=${QB11_ABS:-$B/r36/abs} QB35_TOPL=${QB36_TOPL:-${QB35_TOPL:-0}}
export QB11_INS=${QB11_INS:-1.035} QB14_HINS=${QB14_HINS:-1.412} QB14_AINS=${QB14_AINS:-0.99}
case $step in
abs) A=$B/r36/$tag; mkdir -p "$A"; R=$B/r35/abs
     ring() { "$PY" -I "$I/r5b/lef_ring.py" "$1" "$2" 1.5 | head -3; }
     # column
     if [ -n "${QB36_COLLEF:-}" ]; then ring "$QB36_COLLEF" "$A/qb_col_blk.lef"; fi
     for c in tt ss ff; do C=$(echo $c | tr a-z A-Z)
       if [ -n "${QB36_COLETM:-}" ]; then v=QB36_COLLAT_$C; lat=${!v:-}
         case $c in tt) lat=${lat:-1.035 0.84};; ss) lat=${lat:-1.57 1.24};; ff) lat=${lat:-0.75 0.60};; esac
         "$PY" -I "$I/r5b/etm_ins.py" "$QB36_COLETM/qb_col_blk_$c.lib" "$A/qb_col_blk_${c}_ins.lib" $lat
         "$PY" -I "$I/r7b/etm_fix.py" "$A/qb_col_blk_${c}_ins.lib" "$A/qb_col_blk_${c}_insfix.lib" | grep -c ETM_FIX
         ln -sf "$QB36_COLETM/qb_col_blk_${c}_lib.db" "$A/"
       else ln -sf "$R/qb_col_blk_${c}_insfix.lib" "$A/"; ln -sf "$B/r5b_blk/qb_col_blk_${c}_lib.db" "$A/"; fi
     done
     # hub / act
     for b in HUB:qb_hub ACT:qb_act2_blk; do u=${b%%:*}; m=${b#*:}; lv=QB36_${u}LEF; ev=QB36_${u}ETM
       if [ -n "${!lv:-}" ]; then ring "${!lv}" "$A/$m.lef"; else cp "$(readlink -f "$R/$m.lef")" "$A/$m.lef"; fi
       # write_abstract_lef sizes the macro by its shapes' bbox, not the die (act: 1966.49 vs die 1970): SIZE = die
       wv=QB36_${u}WH; wh=${!wv:-}; [ $u = ACT ] && wh=${wh:-900 1970}
       if [ -n "$wh" ]; then set -- $wh; sed -i "/^MACRO $m/,/^END $m/ s/^\(\s*\)SIZE .*/\1SIZE $1 BY $2 ;/" "$A/$m.lef"; echo "R36_SIZE $m -> $1 x $2"; fi
       for c in tt ss ff; do
         if [ -n "${!ev:-}" ]; then ln -sf "${!ev}/${m}_$c.lib" "$A/"; ln -sf "${!ev}/${m}_${c}_lib.db" "$A/"
         else ln -sf "$(readlink -f "$R/${m}_$c.lib")" "$A/${m}_$c.lib"; [ -e "$R/${m}_${c}_lib.db" ] && ln -sf "$(readlink -f "$R/${m}_${c}_lib.db")" "$A/${m}_${c}_lib.db"; fi
       done
     done
     for f in "$A"/*.lef; do echo "VIEW $(basename "$f") size $(grep -m1 "^\s*SIZE [0-9]" "$f" | xargs) pg_pins $(grep -c 'USE POWER\|USE GROUND' "$f") antenna_stmts $(grep -c ANTENNA "$f")"; done
     ls -la "$A" ;;
tfp|tpnr)
     . "$root/flow/tsmc65/common/tool.sh"; QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY
     export QB_SYN=${QB_SYN:-r35_ptr} QB11_PER=$per QB14_HUBX=${QB14_HUBX:-40} QB_NB=${QB_NB:-800}
     export QB_PDN_BLKX=${QB_PDN_BLKX-"qb_hub qb_act2_blk"} QB35_GRTHOLD=${QB35_GRTHOLD:-0}
     export QB_IO_LAT=${QB_IO_LAT:-$QB35_TOPL} QB11_GR_ITER=${QB11_GR_ITER:-5} QB_PC_HOOK=${QB_PC_HOOK-$I/r35/pc_setup_only.tcl} QB_POSTCTS=${QB_POSTCTS:-1} QB15_GADJ_L=${QB15_GADJ_L-"M2-M3 0.6"} QC_PNR_THREADS=${QC_PNR_THREADS:-16}
     cfg=$here/top.cfg; d=$B/pnr/$tag
     case $step in
     tfp) QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag" || exit 1
          ( cd "$d" && QB_RUN=$d "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" -no_init -no_splash -exit "$I/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
          "$PY" -I "$I/r14/fp14.py" "$d/macros.txt" "$QB11_ABS" "$d/mplace.tcl" || exit 1
          QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag"
          n=$(grep -c "check_power_grid true" "$d/summary.txt"); echo "R36_PG check_power_grid true $n of 2"
          # PSM cannot see through block abstracts: islands that lie inside a hard block (on its PG pins, joined by the
          # block's own grid) are listed but tolerated; any unconnected node outside the blocks fails the step.
          nin=$(grep PSM-0038 "$d/openroad.log" | wc -l)
          nout=$(grep "PSM-0038.*location" "$d/openroad.log" | sed 's/.*location (\([0-9.]*\)um, \([0-9.]*\)um).*/\1 \2/' | awk -v B="${QB36_PGBB:-40 0 4030 1950.8}" 'BEGIN{split(B,b," ")} {if(!($1>=b[1]&&$1<=b[3]&&$2>=b[2]&&$2<=b[4])) n++} END{print n+0}')
          echo "R36_PG unconnected nodes $nin, outside the hub bbox (${QB36_PGBB:-40 0 4030 1950.8}) $nout"
          [ "$n" = 2 ] || [ "$nout" = 0 ] || { echo "R36_FAIL power grid check"; exit 1; } ;;
     tpnr) QB_GRT_STOP=1 QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag"
           [ -f "$d/db/grt.odb" ] || { echo "R36_FAIL no db/grt.odb"; exit 1; } ;;
     esac ;;
tdr) QB_DR_ITER=${QB_DR_ITER:-64} QB8_DR_THREADS=${QB8_DR_THREADS:-16} "$I/r8/run.sh" dr "$tag" || exit 1
     cd "$root" && QC_SPEF_UNESC=1 QB_SPEF_CORNERS="tt ss" "$I/pnr/run.sh" spef "$tag" ;;
pgchk) d=$B/pnr/$tag
     R36_DB=$per "$I/r29/or29.sh" "$tag" "$here/pgdump.tcl" r36_pgdump.log; grep R36_PGDUMP "$d/r36_pgdump.log"
     a=(); for m in qb_col_blk qb_hub qb_act2_blk; do u=$(echo ${m#qb_} | cut -c1-3 | tr a-z A-Z); v=QB36_${u}LEF; [ -n "${!v:-}" ] && a+=("$m=${!v}"); done
     [ ${#a[@]} -gt 0 ] && "$PY" -I "$here/pgovl.py" "$d/rpt/r36_pg.txt" "${a[@]}" ;;
tpt) # as impl/r35/run35.sh tpt (pt_chip.tcl per corner) with QC_SDC impl/r36/pt_top_sdc.tcl and the views' ETM dbs
     A=$QB11_ABS; d=$B/pnr/$tag
     for c in ${QB35_PTC:-tt ss}; do
     ( . "$root/flow/tsmc65/common/tool.sh"; cd "$d" && . ./kit.env; set -a; . "$B/syn/${QB_SYN:-r35_ptr}/run.env"; set +a
       C=$(echo $c | tr a-z A-Z); v=QC_EXTRA_DB_$C; m=""
       for f in ${!v}; do case $f in *qb_col_blk*) ;; *) m="$m $f" ;; esac; done
       export QC_EXTRA_DB_$C="$m $A/qb_col_blk_${c}_lib.db $A/qb_hub_${c}_lib.db $A/qb_act2_blk_${c}_lib.db"
       export QC_SDC=$here/pt_top_sdc.tcl QC_PERIOD=$per
       QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c qc_tool "pt_chip_$c.log" pt_shell -f "$I/r5b/pt_chip.tcl"
       echo "PT_CHIP $c errors $(grep -c '^Error' pt_chip_$c.log)"; cat "pt_chip_$c.txt" ) &
     done; wait
     grep -h "spef_nets" "$d"/pt_chip_*.txt ;;
*) sed -n '2,16p' "$0"; exit 1 ;;
esac
echo "R36_DONE $step $tag $(date +%T)"
