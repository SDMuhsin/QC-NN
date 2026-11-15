#!/usr/bin/env bash
# R6a: top DC of the narrow host port (results/r6a.md section 3) = the R5b top DC recipe (impl/r5b/run.sh syn: R4b
# recipe, R5e head FW 128, core = 8 R5d block ETMs) + define QB_HPW (default 144), tag r6a_hpw<W>.  On tau6 with the
# R5b block views in $QC_BUILD/r5b_blk; compare with syn/r5b_top (results/r5b/dc_top.txt).
set -eu
here=$(cd "$(dirname "$0")" && pwd); W=${1:-144}
QB_GEN=r6a_gen$W QB_DEFS_EXTRA="+define+QB_HPW=$W" QB_SYN_TAG=r6a_hpw$W "$here/../r5b/run.sh" syn
