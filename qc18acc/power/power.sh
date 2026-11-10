#!/usr/bin/env bash
# PrimeTime PX power of a QC18-ACC gate-level run (qc18acc/gls/run_gls.sh) from its SAIF, on the GLS host:
#   qc18acc/power/power.sh [-H host=usask] [-p period_ns=2.5] [-o results_subdir=power] [-e] <syn_tag> <zd|sdf>
# -e: also the PE-internal breakdown (pe_power.tcl, v2 netlists) -> <mode>_<p>ns_pe.txt
# SAIF: $QC_RDIR/gls/<tag>/qa_top_img0.saif (zd) or qa_top_img0_sdf.saif (sdf), simulated at the TB clock 2.5 ns.
# -p other than 2.5: the SAIF is rescaled first (saif_scale.py: same toggles per cycle at the new period).
# pt_power.tcl (tt, synthesis WLM, synthesis SDC at -p) runs in $QC_RDIR/gls/<tag>/power/<mode>_<p>ns/; the
# reports stay on the host, the summaries (design names only) are copied to qc18acc/results/power/<mode>_<p>ns{,_blocks,_macros}.txt
#   (_macros: datatable access-energy model of the macros, macro_dat.py).
# Environment: QC_RDIR (default /tmp/ckp908/qc18acc); QA_V=3 / 4: the v3 / v4 macro set (QA_MACROS of pt_power.tcl).
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
H=usask; P=2.5; SIMP=2.5; OD=power; PE=0
while getopts "H:p:o:e" o; do case $o in H) H=$OPTARG;; p) P=$OPTARG;; o) OD=$OPTARG;; e) PE=1;; *) sed -n 2,11p "$0"; exit 2;; esac; done
shift $((OPTIND - 1))
T=${1:?syn_tag}; MODE=${2:?zd|sdf}
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
MAC="qa_act_1024x64m8 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2"
[ "${QA_V:-2}" = 3 ] && MAC="qa_act_512x64m4 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2"
[ "${QA_V:-2}" = 4 ] && MAC="qa_act_256x128m2 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2"
G=$RDIR/gls/$T; SYN=$RDIR/build/syn/$T; R=$RDIR/repo
SFX=""; [ "$MODE" = sdf ] && SFX=_sdf
SAIF=$G/qa_top_img0$SFX.saif
D=$G/power/${MODE}_${P}ns
OUTL=$Q/../results/$OD; mkdir -p "$OUTL"
DBTT=$(ssh "$H" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
DATW=""
if [ "${QA_V:-2}" = 4 ]; then   # v4 act writes per SAIF cycle: output words / image (compile4.ops) / SAIF window (GLS log)
    LOC=${QC_LOCAL:-/tmp/root/qc18acc4}
    NW=$(cd "$Q/../.." && python3 -m qc18acc.compile4.ops --writes "$LOC/export_rtl")
    NC=$(sed -n 's/^SAIF .*(\([0-9]*\))$/\1/p' "$LOC/gls_$T$SFX.log" | head -1)
    DATW="qa_act_256x128m2:$(python3 -c "print($NW / $NC)"),qa_wgt_4096x80m8:0,qa_par_4096x72m8:0,qa_dsc_256x32m2:0"
    echo "act writes $NW / $NC SAIF cycles; no weight / param / desc writes between START and DONE -> $DATW"
fi
ssh "$H" "set -e; cd $R && git pull -q --ff-only; mkdir -p $D; test -s $SAIF
  S=$SAIF
  if [ $P != $SIMP ]; then S=$D/scaled.saif; python3 -I qc18acc/power/saif_scale.py \$(python3 -c 'print($P / $SIMP)') $SAIF > \$S; fi
  cd $D; tcsh -f -c 'source $R/flow/tsmc65/site/site.csh; setenv QC_FLOW $R/flow/tsmc65; setenv SYN $SYN; \
    setenv QC_SDC $R/qc18acc/impl/constraints.sdc; setenv QC_PERIOD $P; setenv QC_EXTRA_DB_TT \"$DBTT\"; setenv QA_MACROS \"$MAC\"; \
    setenv SAIF '\$S'; setenv OUT $D/pt; pt_shell -f $R/qc18acc/power/pt_power.tcl >& pt.log'
  grep '^Error' pt.log | sort | uniq -c | head; sed -n '/Power Group/,/^ *Total/p' pt.txt
  if [ $PE = 1 ]; then tcsh -f -c 'source $R/flow/tsmc65/site/site.csh; setenv QC_FLOW $R/flow/tsmc65; setenv SYN $SYN; \
    setenv QC_SDC $R/qc18acc/impl/constraints.sdc; setenv QC_PERIOD $P; setenv QC_EXTRA_DB_TT \"$DBTT\"; setenv QA_MACROS \"$MAC\"; \
    setenv SAIF '\$S'; setenv OUT $D/pt; pt_shell -f $R/qc18acc/power/pe_power.tcl >& pt_pe.log'
    grep '^Error' pt_pe.log | sort | uniq -c | head; cat pt_pe.txt; fi
  . $R/flow/tsmc65/site/sram.sh; QA_DAT_WRITES=$DATW python3 -I $R/qc18acc/power/macro_dat.py \$QC_MC_OUT pt_macros.txt > pt_macro_dat.txt; cat pt_macro_dat.txt"
scp -q "$H:$D/pt.txt" "$OUTL/${MODE}_${P}ns.txt"
scp -q "$H:$D/pt_blocks.txt" "$OUTL/${MODE}_${P}ns_blocks.txt"
scp -q "$H:$D/pt_macro_dat.txt" "$OUTL/${MODE}_${P}ns_macros.txt"
[ $PE = 1 ] && scp -q "$H:$D/pt_pe.txt" "$OUTL/${MODE}_${P}ns_pe.txt"
echo "power: $OUTL/${MODE}_${P}ns{,_blocks,_macros}.txt"
