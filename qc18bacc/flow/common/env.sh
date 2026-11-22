# Sourced by every qc18bacc flow shell script (bash):
#   QBF   this flow (qc18bacc/flow)          ROOT  repository root (flow/tsmc65 = the shared OpenROAD / DC / PT flow)
#   B     build root QC_BUILD [/tmp/$USER/qc18bacc/build]; P&R runs in $B/pnr/<tag>
#   TOOLS QC_TOOLS [/tmp/$USER/tools]; PY / OR = its python3 / openroad
#   qb_kit  sources flow/tsmc65 common/tool.sh (FLOW, qc_tool) and exports QC_KIT, QC_PY
QBF=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); ROOT=$(cd "$QBF/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; PY=$TOOLS/env/bin/python3; OR=$TOOLS/env/bin/openroad
qb_kit() {
    . "$ROOT/flow/tsmc65/common/tool.sh"
    QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY
}
