#!/usr/bin/env bash
# R8a: full-chip DC topo = the R7h recipe (impl/r5b/run.sh syn, R4b + FW128 + 8 R5d block ETMs, 1.65 ns tt, defines
# QB_HPW=144 QB_TOP_RSH=2 QB_HEAD_PCOL=1) + the R8a defines given as $2 (e.g. "+QB_HEAD_IREG=1+QB_TOP_WBQ=1"), tag $1.
#   qc18bacc/impl/r8a/syn.sh <tag> <+DEF=V...>      (on tau, repository root; QC_BUILD as impl/r4; QC_CORES default 6)
set -eu
here=$(cd "$(dirname "$0")" && pwd); T=${1:?tag}; X=${2:-}
export QC_CORES=${QC_CORES:-6}
QB_GEN=${T}_gen QB_DEFS_EXTRA="+define+QB_HPW=144+QB_TOP_RSH=2+QB_HEAD_PCOL=1$X" QB_SYN_TAG=$T "$here/../r5b/run.sh" syn
