#!/usr/bin/env bash
# Post-route of a routed qb_pe_hb run (results/pnr_pe.md), on the build host from the repository root:
#   qc18bacc/impl/hard/pe_post.sh <tag>   def2spef ss + ff, PrimeTime tt / ss (pt_post_core.tcl at QB_PT_PERIOD),
#                                          abstract LEF (write_abstract_lef, exact shapes: bloated M7 OBS blocks the PG vias), ETMs tt / ss / ff
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
tag=$1; export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; dir=$QC_BUILD/pnr/$tag
[ -n "${QB_ABS_ONLY:-}" ] || QB_SPEF_CORNERS="ss ff" "$root/qc18bacc/impl/pnr/run.sh" spef "$tag"
[ -n "${QB_ABS_ONLY:-}" ] || QB_PT_PERIOD=${QB_PT_PERIOD:-2.0} "$root/qc18bacc/impl/pnr/run.sh" pt "$tag"
. "$root/flow/tsmc65/common/tool.sh"
export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
cat > "$dir/abs.tcl" <<EOT
source \$::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $dir
source \$::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load finish
write_abstract_lef ${QB_ABS_ARGS:--bloat_factor 0} $dir/out/qb_pe_hb.lef
exit
EOT
( cd "$dir" && QC_FLOW=$FLOW QC_PNR_OUT=$dir QC_PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3 \
  ${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad -no_init -no_splash -exit -log abs.log abs.tcl > abs.out 2>&1 < /dev/null )
echo "ABS_DONE $(grep -c 'PIN' $dir/out/qb_pe_hb.lef)"
. "$dir/kit.env"; set -a; . "$(dirname "$NETLIST")/run.env"; set +a
export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0}
[ -n "${QB_ABS_ONLY:-}" ] && { echo PE_POST_DONE; exit 0; }
for c in tt ss ff; do
    ( cd "$dir" && QC_PNR_OUT=$dir QC_CORNER=$c qc_tool "etm_$c.log" pt_shell -f "$here/pe_etm.tcl" )
    echo "ETM $c $(grep -c '^Error' $dir/etm_$c.log) errors; $(ls $dir/out/etm/ 2>/dev/null | tr '\n' ' ')"
done
echo PE_POST_DONE
