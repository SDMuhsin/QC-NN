# Sourced by the run_*.sh scripts.  Sets FLOW, ROOT, BUILD and defines qc_tool.
FLOW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$(cd "$FLOW/../.." && pwd)
BUILD=${QC_BUILD:-$ROOT/build/tsmc65}
[ -f "$FLOW/site/site.csh" ] || { echo "missing $FLOW/site/site.csh (see flow/tsmc65/README.md, Site files)"; exit 1; }
export QC_FLOW=$FLOW QC_ROOT=$ROOT

# qc_tool <log> <command ...>: run a command in the site tool environment (tcsh), log to <log>;
# wall time and peak memory go to <log>.time when GNU time exists.  Returns the command's exit status.
qc_tool() {
    local log=$1; shift
    local tv=(); [ -x /usr/bin/time ] && tv=(/usr/bin/time -v -o "$log.time")
    "${tv[@]}" tcsh -f -c "source $FLOW/site/site.csh; $*" > "$log" 2>&1 < /dev/null
}
# qc_time <log>: one summary line from <log>.time
qc_time() {
    [ -f "$1.time" ] && awk -F': ' '/Elapsed/ { e = $2 } /Maximum resident/ { m = $2 }
        END { printf "wall %s peak_rss_mb %.0f\n", e, m / 1024 }' "$1.time"
}
