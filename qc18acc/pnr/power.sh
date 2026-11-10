#!/usr/bin/env bash
# PrimeTime PX of the ROUTED QC18-ACC with the v2 SDF SAIF of image 0 (pt_power_post.tcl), on the P&R host:
#   qc18acc/pnr/power.sh [-H host=usask] [-t pnr_tag=qa_pnr] [-s syn_tag=qa2_w3.3] <period_ns>
# QA_V=3: the v3 design (syn tag default qa3_w3.3, v3 macro set, summaries -> qc18acc/results/pnr_v3/<pnr_tag>_post_<p>ns*).
# QA_V=4: the v4 design (qa4_w3.3, v4 macro set, results/pnr_v4/; act-macro writes from the program as power/power.sh:
#   QA_DAT_WRITES, no weight / param / desc writes between START and DONE).
# The SAIF ($QC_RDIR/gls/<syn_tag>/qa_top_img0_sdf.saif, TB clock 2.5 ns) is flattened once (saif_flat.py) and
# rescaled to <period_ns> (saif_scale.py, same toggles per cycle); macro access energy from the datatables
# (macro_dat.py, tt 1.0 V).  Summaries -> qc18acc/results/pnr/post_<p>ns{,_blocks,_macros}.txt (design names only).
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
H=usask; T=qa_pnr; S=qa2_w3.3; SIMP=2.5; OD=pnr
MAC="qa_act_1024x64m8 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2"
if [ "${QA_V:-2}" = 3 ]; then S=qa3_w3.3; OD=pnr_v3; MAC="qa_act_512x64m4 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2"; fi
if [ "${QA_V:-2}" = 4 ]; then S=qa4_w3.3; OD=pnr_v4; MAC="qa_act_256x128m2 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2"; fi
while getopts "H:t:s:" o; do case $o in H) H=$OPTARG;; t) T=$OPTARG;; s) S=$OPTARG;; *) sed -n 2,6p "$0"; exit 2;; esac; done
shift $((OPTIND - 1))
P=${1:?period_ns}
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
R=$RDIR/repo; PNR=$RDIR/build/pnr/$T; SYN=$RDIR/build/syn/$S; G=$RDIR/gls/$S
D=$PNR/power/post_${P}ns
OUTL=$Q/../results/$OD; mkdir -p "$OUTL"
PFX=post_${P}ns; if [ "$OD" != pnr ] || [ "$T" != qa_t1 ]; then PFX=${T}_post_${P}ns; fi   # v2 run qa_t1: the names of results/pnr.md
DBTT=$(ssh "$H" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
DATW=""
if [ "${QA_V:-2}" = 4 ]; then   # v4 act writes per SAIF cycle (as qc18acc/power/power.sh)
    LOC=${QC_LOCAL:-/tmp/root/qc18acc4}
    NW=$(cd "$Q/../.." && python3 -m qc18acc.compile4.ops --writes "$LOC/export_rtl")
    NC=$(sed -n 's/^SAIF .*(\([0-9]*\))$/\1/p' "$LOC/gls_${S}_sdf.log" | head -1)
    DATW="qa_act_256x128m2:$(python3 -c "print($NW / $NC)"),qa_wgt_4096x80m8:0,qa_par_4096x72m8:0,qa_dsc_256x32m2:0"
    echo "act writes $NW / $NC SAIF cycles -> $DATW"
fi
ssh "$H" "set -e; cd $R && git pull -q --ff-only; mkdir -p $D; cd $D
  F=$PNR/power/flat_sdf.saif
  [ -s \$F ] || python3 -I $R/qc18acc/pnr/saif_flat.py $G/qa_top_img0_sdf.saif qa_tb/dut > \$F
  python3 -I $R/qc18acc/power/saif_scale.py \$(python3 -c 'print($P / $SIMP)') \$F > scaled.saif
  tcsh -f -c 'source $R/flow/tsmc65/site/site.csh; setenv QC_FLOW $R/flow/tsmc65; setenv PNR $PNR; \
    setenv QC_SDC $R/qc18acc/impl/constraints.sdc; setenv QC_PERIOD $P; setenv QC_EXTRA_DB_TT \"$DBTT\"; setenv QA_MACROS \"$MAC\"; \
    setenv SAIF $D/scaled.saif; setenv OUT $D/pt; pt_shell -f $R/qc18acc/pnr/pt_power_post.tcl >& pt.log'
  grep '^Error' pt.log | sort | uniq -c | head; sed -n '/Power Group/,/^ *Total/p' pt.txt; cat pt_blocks.txt
  . $R/flow/tsmc65/site/sram.sh; QA_DAT_WRITES=$DATW python3 -I $R/qc18acc/power/macro_dat.py \$QC_MC_OUT pt_macros.txt > pt_macro_dat.txt
  cat pt_macro_dat.txt; rm -f scaled.saif"
scp -q "$H:$D/pt.txt" "$OUTL/$PFX.txt"
scp -q "$H:$D/pt_blocks.txt" "$OUTL/${PFX}_blocks.txt"
scp -q "$H:$D/pt_macro_dat.txt" "$OUTL/${PFX}_macros.txt"
echo "POWER_POST_DONE $T $P"
