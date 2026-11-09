#!/usr/bin/env bash
# QC18-ACC at a low-voltage cell corner (default tt 0.8 V 25 C, tcbn65gplustc0d8_ccs) on the GLS host:
#   qc18acc/power/lowv.sh [-H host=usask] [-l lib=tcbn65gplustc0d8_ccs] [-v volt=0.8] sta   <syn_tag>
#   qc18acc/power/lowv.sh [-H ...] [-l ...] [-v ...]                                 power <syn_tag> <period_ns>
# sta:   lowv_sta.tcl (cells at the low-voltage library, macros tt 1.0 V views: all / logic-only / macro paths)
#        -> qc18acc/results/lowv/sta_<lib>.txt
# power: pt_power.tcl with QC_PT_LIB = <lib> on the SDF SAIF of the v2 GLS (rescaled to <period_ns>, same toggles
#        per cycle), then macro_dat.py with the datatable energies x (volt / 1.0)^2 (MODELLED: the ARM compilers of
#        the kit have no corner below 0.9 V) -> qc18acc/results/lowv/sdf_<p>ns_<lib>{,_blocks,_macros}.txt; lowv.py combines.
# Environment: QC_RDIR (default /tmp/ckp908/qc18acc).
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
H=usask; LIB=tcbn65gplustc0d8_ccs; V=0.8; SIMP=2.5
while getopts "H:l:v:" o; do case $o in H) H=$OPTARG;; l) LIB=$OPTARG;; v) V=$OPTARG;; *) sed -n 2,9p "$0"; exit 2;; esac; done
shift $((OPTIND - 1))
CMD=${1:?sta|power}; T=${2:?syn_tag}
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
G=$RDIR/gls/$T; SYN=$RDIR/build/syn/$T; R=$RDIR/repo
OUTL=$Q/../results/lowv; mkdir -p "$OUTL"
DBTT=$(ssh "$H" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
ENV="source $R/flow/tsmc65/site/site.csh; setenv QC_FLOW $R/flow/tsmc65; setenv SYN $SYN; \
  setenv QC_SDC $R/qc18acc/impl/constraints.sdc; setenv QC_EXTRA_DB_TT \"$DBTT\"; \
  setenv QC_PT_CORNER tt08; setenv QC_PT_LIB $LIB"
case $CMD in
sta)
    D=$G/lowv/sta_$LIB
    ssh "$H" "set -e; cd $R && git pull -q --ff-only; mkdir -p $D; cd $D
      tcsh -f -c '$ENV; setenv QC_PERIOD 3.3; setenv OUT $D/sta; pt_shell -f $R/qc18acc/power/lowv_sta.tcl >& sta.log'
      grep '^Error' sta.log | sort | uniq -c | head; cat sta.txt"
    scp -q "$H:$D/sta.txt" "$OUTL/sta_$LIB.txt" ;;
power)
    P=${3:?period_ns}
    D=$G/lowv/sdf_${P}ns_$LIB; SAIF=$G/qa_top_img0_sdf.saif
    ES=$(python3 -c "print(($V / 1.0) ** 2)")
    ssh "$H" "set -e; cd $R && git pull -q --ff-only; mkdir -p $D; test -s $SAIF; cd $D
      python3 -I $R/qc18acc/power/saif_scale.py \$(python3 -c 'print($P / $SIMP)') $SAIF > scaled.saif
      tcsh -f -c '$ENV; setenv QC_PERIOD $P; setenv SAIF $D/scaled.saif; setenv OUT $D/pt; pt_shell -f $R/qc18acc/power/pt_power.tcl >& pt.log'
      grep '^Error' pt.log | sort | uniq -c | head; sed -n '/Power Group/,/^ *Total/p' pt.txt
      . $R/flow/tsmc65/site/sram.sh; python3 -I $R/qc18acc/power/macro_dat.py \$QC_MC_OUT pt_macros.txt tt_1p0v_25c $ES > pt_macro_dat.txt
      cat pt_macro_dat.txt; rm -f scaled.saif"
    scp -q "$H:$D/pt.txt" "$OUTL/sdf_${P}ns_$LIB.txt"
    scp -q "$H:$D/pt_blocks.txt" "$OUTL/sdf_${P}ns_${LIB}_blocks.txt"
    scp -q "$H:$D/pt_macro_dat.txt" "$OUTL/sdf_${P}ns_${LIB}_macros.txt" ;;
*)  sed -n 2,9p "$0"; exit 2 ;;
esac
echo "LOWV_DONE $CMD $T"
