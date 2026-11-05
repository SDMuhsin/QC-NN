#!/usr/bin/env bash
# Front-end views of compiled SRAM / register-file macros (ARM memory compilers of the kit), run on the server.
#   flow/tsmc65/sram/mc_gen.sh sweep <macros.txt>   datatable only for every line (area, access / cycle time at ss)
#   flow/tsmc65/sram/mc_gen.sh gen   <macros.txt>   liberty (4 corners), Verilog model, footprint (.vclef = .lef) and
#                                                   datatable per line; .lib -> .db (lib2db.tcl); manifest.txt
#   flow/tsmc65/sram/mc_gen.sh dbonly               only the .lib -> .db step and the manifest
#   flow/tsmc65/sram/mc_gen.sh clean                remove the staged compilers / runtime from the scratch
# <macros.txt>: one macro per line, '#' comments:
#   <instance> <compiler> <words> <bits> <mux> [<option>=<value> ...]     e.g.  m1024x64 sram_sp_adv 1024 64 8 write_mask=on wp_size=8
# Site settings (git-ignored site/sram.sh, template site/sram.example.sh): compiler dir, Java 8 runtime, scratch,
# output dir (host-local, QC_MC_OUT/<instance>/), the four characterisation corners, Library Compiler setup.
#
# Host workarounds (from a known-good recipe):
#   - the compilers' bundled 32-bit runtime does not start, so a system Java 8 runs the generator main class
#     directly, headless, with the compiler dir as its base dir;
#   - the 32-bit helper programs stat() their own files, which fails on the NFS kit tree (inode numbers above
#     2^32): the compiler dir is copied to the host-local scratch;
#   - the footprint generator calls <java.home>/../jre_tiling/bin/java: the runtime is copied and linked so;
#   - the compiler accepts exactly four -corners;
#   - every generated liberty names its library USERLIB: renamed to <instance>_<corner>_syn per file.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SITE=$HERE/../site/sram.sh
[ -f "$SITE" ] || { echo "missing $SITE (template site/sram.example.sh)"; exit 1; }
. "$SITE"
S=$QC_MC_SCRATCH
mkdir -p "$S/kit" "$QC_MC_OUT"; chmod 700 "$S"

stage() {   # stage <compiler>: host-local copy of the compiler and of the Java runtime
    [ -d "$S/kit/$1" ] || cp -r "$QC_MC_KIT/$1" "$S/kit/" || { echo "MC_ERROR staging $1"; exit 1; }
    if [ ! -x "$S/jvm/jre/bin/java" ]; then
        mkdir -p "$S/jvm/jre_tiling/bin"
        cp -rL "$QC_MC_JRE" "$S/jvm/jre" || { echo "MC_ERROR staging runtime"; exit 1; }
        ln -sf "$S/jvm/jre/bin/java" "$S/jvm/jre_tiling/bin/java"
    fi
}
run_mc() {  # run_mc <compiler> <dir> <views...> <-option value ...>: one generator run in <dir>, log gen.log
    local c=$1 d=$2; shift 2
    stage "$c"; mkdir -p "$d"
    ( cd "$d" || exit 1
      timeout 900 env LANG=C LC_ALL=C LD_LIBRARY_PATH= "$S/jvm/jre/bin/java" -Djava.awt.headless=true -Xmx2g \
          -Dbasedir="$S/kit/$c" -cp "$S/kit/$c/lib/gui.zip" Main "$@" -corners "$QC_MC_CORNERS" \
          < /dev/null > gen.log 2>&1 )
}
mc_opts() { # mc_opts <words> <bits> <mux> <inst> [k=v ...] -> generator options
    local w=$1 b=$2 m=$3 i=$4; shift 4
    printf -- '-words %s -bits %s -mux %s -instname %s' "$w" "$b" "$m" "$i"
    local kv; for kv in "$@"; do printf -- ' -%s %s' "${kv%%=*}" "${kv#*=}"; done
}
dat_line() {  # dat_line <datfile>: footprint and timing of the first corner (ss), margin setting 0
    awk '$1 == "geomx" { x = $2 } $1 == "geomy" { y = $2 } $1 == "ring_size" { r = $2 }
         $1 == "ta0" { a = $2 } $1 == "tcyc0" { c = $2 }
         END { printf "w_um %.1f h_um %.1f macro_um2 %.0f core_um2 %.0f ta_ss_ns %s tcyc_ss_ns %s\n",
               x + 2 * r, y + 2 * r, (x + 2 * r) * (y + 2 * r), x * y, a, c }' "$1"
}
shapes() {  # shapes <macros.txt>: the macro lines without comments
    sed 's/#.*//' "$1" | awk 'NF >= 5'
}
manifest() {  # one line per macro in QC_MC_OUT: files present, ss footprint / timing
    local m=$QC_MC_OUT/manifest.txt
    {   echo "# macro views on $(hostname -s):$QC_MC_OUT  corners $QC_MC_CORNERS  $(date +%F)"
        for d in "$QC_MC_OUT"/*/; do
            i=$(basename "$d"); [ -f "$d/$i.dat" ] || continue
            echo "$i $(head -1 "$d/spec.txt" 2>/dev/null) | $(dat_line "$d/$i.dat") | lib $(ls "$d"/*_syn.lib 2>/dev/null | wc -l) db $(ls "$d"/*_syn.db 2>/dev/null | wc -l) v $(ls "$d/$i.v" 2>/dev/null | wc -l) lef $(ls "$d/$i.lef" 2>/dev/null | wc -l)"
        done; } > "$m"
    sed 's/^/MANIFEST /' "$m"
}

case "${1:-}" in sweep|gen) [ -f "${2:-}" ] || { echo "MC_ERROR no macro list '${2:-}'"; exit 1; } ;; esac
case "${1:-}" in
sweep)
    shapes "${2:-}" | while read -r i c w b m kv; do
        d=$S/sweep/$i; rm -rf "$d"
        # shellcheck disable=SC2086
        run_mc "$c" "$d" ascii $(mc_opts "$w" "$b" "$m" "$i" $kv)
        if [ -f "$d/$i.dat" ]; then echo "SWEEP $i $c ${w}x$b mux $m $kv: $(dat_line "$d/$i.dat")"
        else echo "SWEEP $i $c ${w}x$b mux $m $kv: FAIL $(grep -m2 -i -E 'error|invalid|range' "$d/gen.log" | tr '\n' ' ')"; fi
    done
    rm -rf "$S/sweep" ;;
gen)
    shapes "${2:-}" | while read -r i c w b m kv; do
        d=$S/gen/$i; rm -rf "$d"
        # shellcheck disable=SC2086
        run_mc "$c" "$d" synopsys verilog vclef-fp ascii $(mc_opts "$w" "$b" "$m" "$i" $kv)
        o=$QC_MC_OUT/$i; rm -rf "$o"; mkdir -p "$o"
        for f in "$d/$i.v" "$d/$i.vclef" "$d/$i.dat" "$d"/${i}_*_syn.lib "$d/gen.log"; do [ -f "$f" ] && cp -f "$f" "$o/"; done
        [ -f "$o/$i.vclef" ] && cp -f "$o/$i.vclef" "$o/$i.lef"   # the footprint is a LEF MACRO abstract (no GDS in the kit)
        echo "$c ${w}x$b mux $m $kv" > "$o/spec.txt"
        for f in "$o"/${i}_*_syn.lib; do
            [ -f "$f" ] || continue
            lb=$(basename "$f" .lib); sed -i "0,/^library *( *[A-Za-z0-9_]* *)/s//library($lb)/" "$f"
        done
        echo "GEN $i $c ${w}x$b mux $m $kv: $(grep -c 'generator succeeded' "$d/gen.log") ok $(grep -c 'generator failed' "$d/gen.log") failed, lib $(ls "$o"/*_syn.lib 2>/dev/null | wc -l)"
    done
    rm -rf "$S/gen"
    ;;&
dbonly|gen)
    ( cd "$QC_MC_OUT" || exit 1
      tcsh -f -c "source $QC_MC_LC_SETUP >& /dev/null; lc_shell -f $HERE/lib2db.tcl" > lib2db.log 2>&1 < /dev/null )
    echo "LIB2DB $(grep -c '^DB_OK' "$QC_MC_OUT/lib2db.log") ok $(grep -c '^DB_FAIL' "$QC_MC_OUT/lib2db.log") failed, errors $(grep -c '^Error' "$QC_MC_OUT/lib2db.log")"
    manifest
    du -sh "$QC_MC_OUT" | sed 's/^/MC_OUT_SIZE /' ;;
clean)
    rm -rf "$S/kit" "$S/jvm" "$S/sweep" "$S/gen"; echo "scratch cleaned" ;;
*)  sed -n '2,10p' "$0"; exit 1 ;;
esac
echo "MC_GEN_DONE"
