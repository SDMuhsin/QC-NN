#!/usr/bin/env bash
# Macro sweep for qc18bacc buffers (run on the server, piped over ssh: bash -s < mc_sweep.sh <list>).
# Same generator recipe as flow/tsmc65/sram/mc_gen.sh (staged compiler + system Java 8), but views 'ascii synopsys'
# and the output is one line per shape: footprint incl. ring and access / cycle time of every corner from the .lib
# (tt and ss). Kit files and views stay in $S/msweep (deleted per shape); only numbers are printed.
# list lines (stdin after the script is not used; list file given as $1 on the server): <inst> <compiler> <w> <b> <mux> [k=v..]
set -u
QC_MC_KIT=/CMC/kits/arm_tsmc65gp-nonCmcPsa/aci
QC_MC_JRE=/usr/lib/jvm/jre-1.8.0
S=/tmp/$USER/qcnn/mc_scratch
QC_MC_CORNERS=ss_0p9v_125c,tt_1p0v_25c,ff_1p1v_m40c,ff_1p1v_125c
stage() {
    [ -d "$S/kit/$1" ] || cp -r "$QC_MC_KIT/$1" "$S/kit/" || { echo "MC_ERROR staging $1"; exit 1; }
    if [ ! -x "$S/jvm/jre/bin/java" ]; then
        mkdir -p "$S/jvm/jre_tiling/bin"; cp -rL "$QC_MC_JRE" "$S/jvm/jre"
        ln -sf "$S/jvm/jre/bin/java" "$S/jvm/jre_tiling/bin/java"
    fi
}
# lib_t <lib>: CLK -> Q cell_rise of the first Q bus at input slew index 4 / load index 4 (0.09 ns, 0.07 pF class)
lib_t() {
    awk '/^ *bus *\( *Q/ {inq=1} inq && /cell_rise/ {c=1} c && /values/ {r=0; next}
         c && r >= 0 && /"/ { r++; if (r == 4) { gsub(/[\\"]/,""); split($0,a,","); printf "%.3f", a[4]; exit } }
         BEGIN {r=-1}' "$1"
}
# dat_t <dat> <col>: max over ta*0 / taa*0 and tcyc*0 keys (index 0) of corner column col (2 = ss, 3 = tt)
dat_t() {
    awk -v c="$2" '$1 ~ /^ta[a-b]?0$/ { if ($c+0 > a) a = $c+0 } $1 ~ /^tcyc[a-b]?0$/ { if ($c+0 > t) t = $c+0 }
         END { printf "%.3f %.3f", a, t }' "$1"
}
mkdir -p "$S/kit" "$S/msweep"
sed 's/#.*//' "$1" | awk 'NF >= 5' | while read -r i c w b m kv; do
    d=$S/msweep/$i; rm -rf "$d"; stage "$c"; mkdir -p "$d"
    opts="-words $w -bits $b -mux $m -instname $i"; for x in $kv; do opts="$opts -${x%%=*} ${x#*=}"; done
    ( cd "$d" && timeout 600 env LANG=C LC_ALL=C LD_LIBRARY_PATH= "$S/jvm/jre/bin/java" -Djava.awt.headless=true -Xmx2g \
        -Dbasedir="$S/kit/$c" -cp "$S/kit/$c/lib/gui.zip" Main ascii synopsys $opts -corners "$QC_MC_CORNERS" \
        < /dev/null > gen.log 2>&1 )
    if [ -f "$d/$i.dat" ]; then
        g=$(awk '$1=="geomx"{x=$2} $1=="geomy"{y=$2} $1=="ring_size"{r=$2} END{printf "w_um %.1f h_um %.1f area_um2 %.0f", x+2*r, y+2*r, (x+2*r)*(y+2*r)}' "$d/$i.dat")
        tt=$(ls "$d"/*tt_1p0v_25c*.lib 2>/dev/null | head -1); ss=$(ls "$d"/*ss_0p9v_125c*.lib 2>/dev/null | head -1)
        echo "MS $i $c $w $b $m $kv | $g | tt dat_ta_tcyc $(dat_t "$d/$i.dat" 3) lib_ta $(lib_t "$tt") | ss dat_ta_tcyc $(dat_t "$d/$i.dat" 2) lib_ta $(lib_t "$ss")"
    else
        echo "MS $i $c $w $b $m $kv | FAIL $(grep -m2 -i -E 'error|invalid|range' "$d/gen.log" | tr '\n' ' ')"
    fi
    [ -n "${KEEP:-}" ] || rm -rf "$d"
done
echo MS_DONE
