#!/usr/bin/env bash
# PrimeTime PX of the ROUTED QC18-ACC with the v2 SDF SAIF of image 0 (pt_power_post.tcl), on the P&R host:
#   qc18acc/pnr/power.sh [-H host=usask] [-t pnr_tag=qa_pnr] [-s syn_tag=qa2_w3.3] <period_ns>
# The SAIF ($QC_RDIR/gls/<syn_tag>/qa_top_img0_sdf.saif, TB clock 2.5 ns) is flattened once (saif_flat.py) and
# rescaled to <period_ns> (saif_scale.py, same toggles per cycle); macro access energy from the datatables
# (macro_dat.py, tt 1.0 V).  Summaries -> qc18acc/results/pnr/post_<p>ns{,_blocks,_macros}.txt (design names only).
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
H=usask; T=qa_pnr; S=qa2_w3.3; SIMP=2.5
while getopts "H:t:s:" o; do case $o in H) H=$OPTARG;; t) T=$OPTARG;; s) S=$OPTARG;; *) sed -n 2,6p "$0"; exit 2;; esac; done
shift $((OPTIND - 1))
P=${1:?period_ns}
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
R=$RDIR/repo; PNR=$RDIR/build/pnr/$T; SYN=$RDIR/build/syn/$S; G=$RDIR/gls/$S
D=$PNR/power/post_${P}ns
OUTL=$Q/../results/pnr; mkdir -p "$OUTL"
DBTT=$(ssh "$H" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
ssh "$H" "set -e; cd $R && git pull -q --ff-only; mkdir -p $D; cd $D
  F=$PNR/power/flat_sdf.saif
  [ -s \$F ] || python3 -I $R/qc18acc/pnr/saif_flat.py $G/qa_top_img0_sdf.saif qa_tb/dut > \$F
  python3 -I $R/qc18acc/power/saif_scale.py \$(python3 -c 'print($P / $SIMP)') \$F > scaled.saif
  tcsh -f -c 'source $R/flow/tsmc65/site/site.csh; setenv QC_FLOW $R/flow/tsmc65; setenv PNR $PNR; \
    setenv QC_SDC $R/qc18acc/impl/constraints.sdc; setenv QC_PERIOD $P; setenv QC_EXTRA_DB_TT \"$DBTT\"; \
    setenv SAIF $D/scaled.saif; setenv OUT $D/pt; pt_shell -f $R/qc18acc/pnr/pt_power_post.tcl >& pt.log'
  grep '^Error' pt.log | sort | uniq -c | head; sed -n '/Power Group/,/^ *Total/p' pt.txt; cat pt_blocks.txt
  . $R/flow/tsmc65/site/sram.sh; python3 -I $R/qc18acc/power/macro_dat.py \$QC_MC_OUT pt_macros.txt > pt_macro_dat.txt
  cat pt_macro_dat.txt; rm -f scaled.saif"
scp -q "$H:$D/pt.txt" "$OUTL/post_${P}ns.txt"
scp -q "$H:$D/pt_blocks.txt" "$OUTL/post_${P}ns_blocks.txt"
scp -q "$H:$D/pt_macro_dat.txt" "$OUTL/post_${P}ns_macros.txt"
echo "POWER_POST_DONE $T $P"
