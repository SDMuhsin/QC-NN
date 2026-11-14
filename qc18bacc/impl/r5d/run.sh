#!/usr/bin/env bash
# R5d (results/r5d.md): the R5c run-B recipe (impl/r5c: 16 PE templates 376 um / density 0.70, tiled FIRM; impl/r5a
# col.cfg knobs, DR 7 iterations) on a new column netlist, then SPEF tt / ss, PT (impl/r5a/post.sh pt), the
# violating-endpoint dump (impl/r5d/hist.sh), DR histogram, and the 8-copy zero-delay GLS (impl/r5a/gls.sh).
#   qc18bacc/impl/r5d/run.sh <tag> <syn tag> <imgdir>...     (on tau, from the repository root; QC_BUILD as R5c)
# Steps can be skipped with R5D_STEPS (default "tiles pnr post gls").  R5D_PNR_PERIOD: P&R (column) SDC period (default
# 2.0 = run B; the templates, PT and GLS stay at 2.0).
set -u
tag=$1; syn=$2; shift 2
root=$PWD; export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
steps=${R5D_STEPS:-tiles pnr post gls}
case " $steps " in *" tiles "*)
  for w in '0 1 2 3' '4 5 6 7' '8 9 10 11' '12 13 14 15'; do
    for r in $w; do QC_PNR_THREADS=4 QC_PNR_TO=place QB_SYN=$syn QB_TILE_W=376 QB_TILE_DENS=0.70 QB_ROW=$r \
      flow/tsmc65/pnr/run_pnr.sh qc18bacc/impl/r5c/pe_tile.cfg ${tag}t$r > $B/${tag}t$r.out 2>&1 & done; wait
  done
  for r in $(seq 0 15); do mkdir -p $B/${tag}tiles/r5c_t$r; cp $B/pnr/${tag}t$r/tile.txt $B/${tag}tiles/r5c_t$r/; done
  echo R5D_TILES_DONE ;;
esac
case " $steps " in *" pnr "*)
  QC_PNR_THREADS=15 QB_CFG=../r5c/col.cfg QB_SYN=$syn QB_BRG=2 QB_PM=seed QB_PNR_PERIOD=${R5D_PNR_PERIOD:-2.0} QB_REPIN=2 QB_RT_LOOPS=0 \
    QB_INC_POST=1 QB_GR_ADJ=0.15 QB_W=380 QB_INC_DENS=0.80 QB_DR_ITER=6 QB_TILE_DIR=$B/${tag}tiles \
    qc18bacc/impl/pnr/run.sh pnr $tag
  echo R5D_PNR_DONE ;;
esac
case " $steps " in *" post "*)
  QB_SPEF_CORNERS=ss qc18bacc/impl/pnr/run.sh spef $tag
  QB_PT_PERIOD=2.0 qc18bacc/impl/r5a/post.sh $tag pt
  qc18bacc/impl/r5d/hist.sh $tag tt 2.0; qc18bacc/impl/r5d/hist.sh $tag ss 3.0
  ${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3 -I qc18bacc/impl/r5a/drc_hist.py $B/pnr/$tag/rpt/drt.drc.rpt \
    > $B/pnr/$tag/drc_hist.txt
  echo R5D_POST_DONE ;;
esac
case " $steps " in *" gls "*)
  # netlist after DRV repair, CTS and the post-CTS setup / hold repair (as R5c: nothing later changes the netlist)
  mkdir -p $B/pnr/$tag/gls
  printf 'read_db db/cts_rt.odb\nwrite_verilog gls/qb_col_blk_cts_rt.v\nexit\n' > $B/pnr/$tag/gls/wv.tcl
  ( cd $B/pnr/$tag && ${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad -no_init -no_splash -exit gls/wv.tcl \
      > gls/wv.log 2>&1 < /dev/null )
  qc18bacc/impl/r5a/gls.sh $tag $B/pnr/$tag/gls/qb_col_blk_cts_rt.v "$@"
  echo R5D_GLS_DONE ;;
esac
echo R5D_DONE $tag
