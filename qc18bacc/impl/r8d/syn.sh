#!/usr/bin/env bash
# R8d: full-chip DC topo = impl/r8a/syn.sh (R7h recipe) with the R8a define set + QB_ACT_S1M=1 + the R8d defines
# (QB_TOP_FPR=1 (R8a) QB_TOP_WBK=1 QB_TOP_FFT=1 QB_SEQ_DEP) + optional extra defines $2, tag $1.
#   qc18bacc/impl/r8d/syn.sh <tag> [+DEF=V...]      (on tau, repository root; QC_BUILD as impl/r4)
set -eu
here=$(cd "$(dirname "$0")" && pwd); T=${1:?tag}; X=${2:-}
R8A="+QB_HEAD_IREG=2+QB_TOP_WBQ=2+QB_ACT_CTXR+QB_ACT_LDR+QB_ACT_CNT+QB_ACT_SRA+QB_SEQ_LPS+QB_SEQ_CMH+QB_SEQ_TKS+QB_PRM_BAR+QB_SEQ_DSP+QB_SEQ_TGO+QB_PRM_NUR+QB_SEQ_NXW+QB_SEQ_RAL"
R8D="+QB_ACT_S1M=1+QB_TOP_FPR=1+QB_TOP_WBK=1+QB_TOP_FFT=1+QB_SEQ_DEP"
exec "$here/../r8a/syn.sh" "$T" "$R8A$R8D$X"
