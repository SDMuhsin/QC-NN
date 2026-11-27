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
# qc_errors <log>: the '^Error' lines of a DC / PrimeTime log but the allowed ones QC_ERR_ALLOW (syn/run_dc.sh,
# sta/run_pt.sh: dc_shell -f / pt_shell -f go on after a failing command and exit 0, so their exit status never saw an
# error of a hook; qc18bacc R101 DC, R102 PrimeTime).  Allowed, each a whole line:
#   PROC-3   DC's helper process cannot connect back on some hosts; harmless (DC goes on in one process).
#   UID-109  for the dont_use globs <lib>/LVL* and <lib>/ISO* (site.tcl QC_DONT_USE): multi-voltage cells, which only the
#            kit's multi-voltage libraries have; the base libraries DC links have none ([M] tcbn65gplus{wc,wcl,tc,bc,lt,ml}
#            _ccs.lib: 816 cells each, 0 LVL* / ISO*), and set_dont_use applies to the other globs' cells.
QC_ERR_ALLOW='^Error: (Could not connect to child process\. \(PROC-3\)|Can'"'"'t find lib_cells matching '"'"'[^/'"'"']+/(LVL|ISO)\*'"'"'\. \(UID-109\))$'
qc_errors() { grep '^Error' "$1" | grep -vE "$QC_ERR_ALLOW"; }
# qc_time <log>: one summary line from <log>.time
qc_time() {
    [ -f "$1.time" ] && awk -F': ' '/Elapsed/ { e = $2 } /Maximum resident/ { m = $2 }
        END { printf "wall %s peak_rss_mb %.0f\n", e, m / 1024 }' "$1.time"
}
