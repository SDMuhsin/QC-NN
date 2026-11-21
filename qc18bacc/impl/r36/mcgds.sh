#!/usr/bin/env bash
# R36: can the kit's ARM compilers emit a layout (gds2) / LVS netlist view?  Mirrors flow/tsmc65/sram/mc_gen.sh run_mc
# (host-local staged compiler + Java 8) with views "<views>" for one macro line.  Output dir <out>.
#   mcgds.sh <out> <compiler> <words> <bits> <mux> <inst> [views ("gds2 lvs")] [k=v ...]
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../../flow/tsmc65/site/sram.sh"
o=${1:?out}; c=$2; w=$3; b=$4; m=$5; i=$6; v=${7:-gds2 lvs}; shift 7 2>/dev/null || shift $#
S=/tmp/$USER/qc18bacc/build/r36/mc; mkdir -p "$S/kit" "$o"; chmod 700 "$S"
[ -d "$S/kit/$c" ] || cp -r "$QC_MC_KIT/$c" "$S/kit/"
if [ ! -x "$S/jvm/jre/bin/java" ]; then mkdir -p "$S/jvm/jre_tiling/bin"; cp -rL "$QC_MC_JRE" "$S/jvm/jre"; ln -sf "$S/jvm/jre/bin/java" "$S/jvm/jre_tiling/bin/java"; fi
opts="-words $w -bits $b -mux $m -instname $i"; for kv in "$@"; do opts="$opts -${kv%%=*} ${kv#*=}"; done
cd "$o" && for vw in $v; do
  timeout 900 env LANG=C LC_ALL=C LD_LIBRARY_PATH= "$S/jvm/jre/bin/java" -Djava.awt.headless=true -Xmx2g -Dbasedir="$S/kit/$c" \
    -cp "$S/kit/$c/lib/gui.zip" Main $vw $opts -corners "$QC_MC_CORNERS" < /dev/null > gen_$vw.log 2>&1
  echo "MCGDS view $vw: $(grep -c 'generator succeeded' gen_$vw.log) ok $(grep -c 'generator failed' gen_$vw.log) failed; $(tail -2 gen_$vw.log | tr '\n' ' ')"
done
ls -la "$o"
