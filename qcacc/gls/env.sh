# Source me (bash) with D=qc|gemmx: environment of nn/gls/run_gls.sh / power.sh for s2.
#   qc     the QC-GeMMX cluster netlist qc_w4.2 (qcacc/impl/run.sh), GLS library /tmp/ckp908/qcacc_gls, qcacc compiler
#          in qc mode (9 calls, requant table, -DNN_QC_RQ), QC tree headers (build/qcacc)
#   gemmx  control: the BASE netlist kul_w4.2p, s2 as int8 ternary weights, 42 per-group calls, base headers; GLS
#          library /tmp/ckp908/qcacc_ctlgls (a copy of the base build's, which stays untouched)
QCNN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
S2=${QC_S2:-/tmp/${USER:-$(id -un)}/qc/final/int8/s2.pt}
export QC_S2=$S2 QCACC_MODE=$D NN_GLS_OUT=$QCNN/build/qcacc/gls NN_GLS_CHECK=qcacc.gls.tcdm_check
export NN_PT_HOOK=$QCNN/qcacc/gls/pt_blocks.tcl
if [ "$D" = qc ]; then
  export KUL_GLS_DIR=${KUL_GLS_DIR:-/tmp/ckp908/qcacc_gls}
  export KUL_GLS_SYN=${KUL_GLS_SYN:-/tmp/ckp908/qcacc_syn/build/syn/qc_w4.2}
  export KUL_GLS_FLOW=${KUL_GLS_FLOW:-/tmp/ckp908/qcacc_syn/tree/flow/tsmc65}
  export KUL_BUILD=$QCNN/build/qcacc NN_GLS_FLAGS=-DNN_QC_RQ
  export NN_GLS_ACC="+acc=n+KULCluster_QcBlockGemm+KULCluster_QcPipelinedRescaleSIMD"
  export NN_COMPILE="python3 -m qcacc.compile.main --mode qc --qparams $S2"
else
  export KUL_GLS_DIR=${KUL_GLS_DIR:-/tmp/ckp908/qcacc_ctlgls}
  export KUL_GLS_SYN=${KUL_GLS_SYN:-/tmp/ckp908/qcnn_kulsyn/build/syn/kul_w4.2p}
  export KUL_BUILD=$QCNN/build/qcacc/ctl NN_GLS_FLAGS=""
  export NN_COMPILE="python3 -m qcacc.compile.main --mode gemmx --per-group --qparams $S2"
fi
