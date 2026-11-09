#!/usr/bin/env bash
# PrimeTime PX power of a QC18-ACC gate-level run (qc18acc/gls/run_gls.sh) from its SAIF, on the GLS host:
#   qc18acc/power/power.sh [-H host=usask] [-p period_ns=2.5] <syn_tag> <zd|sdf>
# SAIF: $QC_RDIR/gls/<tag>/qa_top_img0.saif (zd) or qa_top_img0_sdf.saif (sdf), simulated at the TB clock 2.5 ns.
# -p other than 2.5: the SAIF is rescaled first (saif_scale.py: same toggles per cycle at the new period).
# pt_power.tcl (tt, synthesis WLM, synthesis SDC at -p) runs in $QC_RDIR/gls/<tag>/power/<mode>_<p>ns/; the
# reports stay on the host, the summaries (design names only) are copied to qc18acc/results/power/<mode>_<p>ns{,_blocks,_macros}.txt
#   (_macros: datatable access-energy model of the macros, macro_dat.py).
# Environment: QC_RDIR (default /tmp/ckp908/qc18acc).
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
H=usask; P=2.5; SIMP=2.5
while getopts "H:p:" o; do case $o in H) H=$OPTARG;; p) P=$OPTARG;; *) sed -n 2,9p "$0"; exit 2;; esac; done
shift $((OPTIND - 1))
T=${1:?syn_tag}; MODE=${2:?zd|sdf}
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
G=$RDIR/gls/$T; SYN=$RDIR/build/syn/$T; R=$RDIR/repo
SFX=""; [ "$MODE" = sdf ] && SFX=_sdf
SAIF=$G/qa_top_img0$SFX.saif
D=$G/power/${MODE}_${P}ns
OUTL=$Q/../results/power; mkdir -p "$OUTL"
DBTT=$(ssh "$H" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
ssh "$H" "set -e; cd $R && git pull -q --ff-only; mkdir -p $D; test -s $SAIF
  S=$SAIF
  if [ $P != $SIMP ]; then S=$D/scaled.saif; python3 -I qc18acc/power/saif_scale.py \$(python3 -c 'print($P / $SIMP)') $SAIF > \$S; fi
  cd $D; tcsh -f -c 'source $R/flow/tsmc65/site/site.csh; setenv QC_FLOW $R/flow/tsmc65; setenv SYN $SYN; \
    setenv QC_SDC $R/qc18acc/impl/constraints.sdc; setenv QC_PERIOD $P; setenv QC_EXTRA_DB_TT \"$DBTT\"; \
    setenv SAIF '\$S'; setenv OUT $D/pt; pt_shell -f $R/qc18acc/power/pt_power.tcl >& pt.log'
  grep '^Error' pt.log | sort | uniq -c | head; sed -n '/Power Group/,/^ *Total/p' pt.txt
  . $R/flow/tsmc65/site/sram.sh; python3 -I $R/qc18acc/power/macro_dat.py \$QC_MC_OUT pt_macros.txt > pt_macro_dat.txt; cat pt_macro_dat.txt"
scp -q "$H:$D/pt.txt" "$OUTL/${MODE}_${P}ns.txt"
scp -q "$H:$D/pt_blocks.txt" "$OUTL/${MODE}_${P}ns_blocks.txt"
scp -q "$H:$D/pt_macro_dat.txt" "$OUTL/${MODE}_${P}ns_macros.txt"
echo "power: $OUTL/${MODE}_${P}ns{,_blocks,_macros}.txt"
