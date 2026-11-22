# Sourced (bash): KLayout batch runs of the Calibre sign-off (results/r38.md; klayout Python wheel $QC_TOOLS/kl_py via
# klrun.py, no klayout binary on tau6) and their layer map $QC_BUILD/drc/r38_map/kl.map (made once: flow/tsmc65 gds_map.py
# of the kit map, LEF OBS -> 255/<n>).
#   kl_map <kitrun>             map path (made from the kit.env LEF / GDSMAP of P&R run <kitrun> if missing)
#   kl_run <script.py> [-rd k=v ...]   klayout -b -r <script.py> ... ; exit status of the script
#   kl_abs <kitrun> <stack 0|1> <out.gds> <macro.lef>...   LEF abstracts -> GDS cells (lef2gds.py; stack 1: pin stack cuts)
_kl_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_kl_tools=${QC_TOOLS:-/tmp/$USER/tools}
kl_kit() { ( cd "${QC_BUILD:-/tmp/$USER/qc18bacc/build}/pnr/$1" && . ./kit.env && echo "${!2}" ); }
kl_map() {
    local M=${QC_BUILD:-/tmp/$USER/qc18bacc/build}/drc/r38_map; mkdir -p "$M"
    if [ ! -f "$M/kl.map" ]; then
        "$_kl_tools/env/bin/python3" -I "$_kl_here/../../../../flow/tsmc65/pnr/py/gds_map.py" "$(kl_kit "$1" GDSMAP)" "$(kl_kit "$1" LEF)" "$M/kl0.map" >&2 || return 1
        awk '{ if ($2 ~ /LEFOBS/) { sub(/,LEFOBS/, "", $2); n++; print; print $1, "LEFOBS", 255, n } else print }' "$M/kl0.map" > "$M/kl.map" || return 1
    fi
    echo "$M/kl.map"
}
kl_run() { PYTHONPATH=$_kl_tools/kl_py${PYTHONPATH:+:$PYTHONPATH} "$_kl_tools/env/bin/python3" "$_kl_here/klrun.py" -b -r "$@"; }
kl_abs() {
    local kr=$1 st=$2 out=$3 map; shift 3; map=$(kl_map "$kr") || return 1
    kl_run "$_kl_here/lef2gds.py" -rd lefs="$(kl_kit "$kr" LEF) $*" -rd layer_map="$map" -rd stack="$st" -rd out="$out" && [ -s "$out" ]
}
