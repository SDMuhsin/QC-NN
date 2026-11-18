#!/usr/bin/env bash
# R26 (results/r26.md): hub with the RTL hook QB_TOP_PTR (pt lookup registered one cycle early).  On tau from the
# snapshot root; every step imports an existing script (no copies):
#   qc18bacc/impl/r26/run26.sh syn             chip DC = impl/r5b/run.sh syn with the r10_rpw define line + QB26_DEFS
#                                              (default +QB_TOP_PTR=1), QB_GEN r26_gen, tag QB_SYN [r26_ptr]
#   qc18bacc/impl/r26/run26.sh part            partition (impl/r10b/run.sh dump part ports sdc) -> QB9_W [$B/r26_w]
#   qc18bacc/impl/r26/run26.sh fp <tag>        floorplan pn2 (impl/r15/run15.sh fp, impl/r22 env, QB22_FP pn QB22_S2S 1)
#   qc18bacc/impl/r26/run26.sh pl <tag>        place .. GRT at the R24 d65t settings (impl/r24/run24.sh pl: QB24_DENS
#                                              0.65, QB24_MODE fix, QB_TNS 10, QB_RT_LOOPS 0)
#   qc18bacc/impl/r26/run26.sh all <tag>       syn part fp pl
#   qc18bacc/impl/r26/run26.sh meas <tag> <db> area / repair-class / pin census (area26.tcl) of db/<db>.odb
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd); I=$root/qc18bacc/impl
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
export QB_SYN=${QB_SYN:-r26_ptr} QB9_W=${QB9_W:-$B/r26_w}
R10W='+define+QB_HPW=144+QB_TOP_RSH=2+QB_HEAD_PCOL=1+QB_HEAD_IREG=2+QB_TOP_WBQ=2+QB_ACT_CTXR+QB_ACT_LDR+QB_ACT_CNT+QB_ACT_SRA+QB_SEQ_LPS+QB_SEQ_CMH+QB_SEQ_TKS+QB_PRM_BAR+QB_SEQ_DSP+QB_SEQ_TGO+QB_PRM_NUR+QB_SEQ_NXW+QB_SEQ_RAL+QB_ACT_S1M=1+QB_TOP_FPR=1+QB_TOP_WBK=1+QB_TOP_FFT=1+QB_SEQ_DEP+QB_ACT_S2M+QB_PRM_COL=1+QB_WB_COL=1'
step=${1:?step}; tag=${2:-}
case $step in
syn)  QB_GEN=${QB_SYN}_gen QB_SYN_TAG=$QB_SYN QB_DEFS_EXTRA="$R10W${QB26_DEFS-+QB_TOP_PTR=1}" "$I/r5b/run.sh" syn ;;
part) for s in dump part ports sdc; do echo "== $s $(date +%T)"; "$I/r10b/run.sh" $s || { echo R26_PART_FAIL $s; exit 1; }; done
      echo R26_PART_OK $(date +%T) ;;
fp)   QB15_FP=${QB15_FP:-mid} QB22_FP=${QB22_FP:-pn} QB22_S2S=${QB22_S2S:-1} QB_SB=${QB_SB:-649} QB15_MPLACE=${QB22_MPLACE:-$I/r22/mplace22.py} \
        QB9_PER=${QB9_PER:-2.30} "$I/r15/run15.sh" fp "$tag" > "$B/pnr/${tag}_fp.out" 2>&1 || { echo R26_FAIL fp; exit 1; }
      grep -h "MPLACE22 pn\|MPLACE9 hub" "$B/pnr/${tag}_fp.out"; echo R26_FP_OK $(date +%T) ;;
pl)   QB24_DENS=${QB24_DENS:-0.65} QB24_MODE=${QB24_MODE:-fix} QB_TNS=${QB_TNS:-10} QB_RT_LOOPS=${QB_RT_LOOPS:-0} \
        "$I/r24/run24.sh" pl "$tag" ;;
all)  "$0" syn && "$0" part && "$0" fp "$tag" && "$0" pl "$tag" ;;
meas) d=$B/pnr/${tag:?tag}
      ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
        cd "$d" && QB_DB=${3:?db} QC_FLOW=$FLOW QC_PNR_OUT=$d "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" -no_init -no_splash -exit \
          "$here/area26.tcl" > "r26_meas_$3.log" 2>&1 < /dev/null ); grep -h "R26_\|^Error" "$d/r26_meas_$3.log" | head -40 ;;
*)    sed -n '2,12p' "$0"; exit 1 ;;
esac
