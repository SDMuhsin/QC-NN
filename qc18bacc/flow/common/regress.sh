#!/usr/bin/env bash
# The regression of the flow (PI rule: every flow change passes it before it may run on the column): the full chain of
# the regression block qb_lane_n (blocks/rgr: pnr eco calibre post views signoff) from a snapshot of one commit,
# compared with the committed reference blocks/rgr/reference.txt.  Run from any directory of the repository checkout;
# ssh command QC_SSH (default ssh), as common/deploy.sh.
#   regress.sh run <commit | tree-ish> <host>   deploy.sh the commit to the snapshot /tmp/<remote user>/qc18bacc/rgr_<run>,
#                                               then the chain detached (common/queue.sh, log dir <run dir>q); prints the
#                                               run, its run dir and the queue.  <run> = rg + the first 7 hex digits of
#                                               the commit (of the tree when a tree id is given) + the first free letter
#   regress.sh check <host> <run> [<commit | tree-ish>]
#                                               exit 0 only if the run is of the flow under test (its snapshot's
#                                               VERSION tree has the archived paths [deploy.sh --paths] of <commit |
#                                               tree-ish>, default HEAD, apart from blocks/rgr/reference.txt), its site
#                                               manifest (VERSION site_md5 lines) and its inputs (the run's summary.txt
#                                               "init inputs" line: md5 of netlist, DC SDC, run.env, the block's
#                                               BLK_INPUTS; common/block.sh blk_inputs) are the reference's, the queue ran exactly the chain and
#                                               every step is ok, the signoff step's verdict (signoff/verdict.sh) is
#                                               SIGNOFF PASS with no FAIL and no MISSING gate and its VERDICT line equals
#                                               the reference's, and the gate set (gate name x corner) equals the
#                                               reference's; prints the difference of the gate sets otherwise
#   regress.sh ref <host> <run> [<commit | tree-ish>]
#                                               writes blocks/rgr/reference.txt of this checkout from <run>, which must
#                                               pass every check but the reference comparison: a changed gate set is a
#                                               deliberate, reviewed reference update (git diff), never a silent one; so
#                                               is a new site manifest or new DC inputs (a re-synthesised netlist)
# The run's own files are read (queue.state, summary.txt, the signoff step's output) and the verdict is re-run from the
# snapshot on the run dir (blocks/rgr/run.sh signoff), which must equal the signoff step's output (check verdict_rerun);
# the snapshot is found by its run name.
set -uo pipefail
die() { echo "REGRESS_FAIL $*" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd); ref=$(cd "$here/.." && pwd)/blocks/rgr/reference.txt
ssh=${QC_SSH:-ssh}
CHAIN="pnr eco calibre post views signoff"
cmd=${1:-}; [ $# = 3 ] || { [ $# = 4 ] && [ "$cmd" != run ]; } \
    || die "usage: regress.sh run <commit | tree-ish> <host> | check <host> <run> [<commit | tree-ish>] | ref <host> <run> [<commit | tree-ish>]"
name_ok() { [[ $1 =~ ^[A-Za-z0-9_.-]+$ ]] || die "'$1' is not a name of [A-Za-z0-9_.-]"; }

# run: snapshot + detached chain
run() {
    local rev=$1 host=$2 id tree user tag l snap out
    name_ok "$host"
    tree=$(git -C "$here" rev-parse --verify --quiet "$rev^{tree}" 2> /dev/null) || die "'$rev' is not a commit or tree"
    id=$(git -C "$here" rev-parse --verify --quiet "$rev^{commit}" 2> /dev/null) || id=$tree
    user=$($ssh "$host" 'printf %s "$USER"') && name_ok "$user" || die "no remote user on $host"
    for l in {a..z} ""; do [ -n "$l" ] || die "no free run name rg${id:0:7}[a-z] on $host"
        tag=rg${id:0:7}$l snap=/tmp/$user/qc18bacc/rgr_$tag
        $ssh "$host" "[ ! -e '$snap' ] && [ ! -e '$snap.part' ]" && break
    done
    bash "$here/deploy.sh" "$rev" "$host:$snap" || die "deploy of $rev to $host:$snap"
    # the chain from the snapshot: spec in the run's queue log dir <run dir>q (a run dir that exists is refused)
    out=$($ssh "$host" bash -s -- "'$snap'" "'$tag'" "'$CHAIN'" "'$(git -C "$here" rev-parse --short "$id")'" << 'EOF'
set -u
snap=$1 tag=$2 chain=$3 id=$4 f=$1/qc18bacc/flow
d=$("$f/blocks/rgr/run.sh" rundir "$tag") || { echo "REGRESS_FAIL rundir"; exit 1; }
[ ! -e "$d" ] && [ ! -e "${d}q" ] || { echo "REGRESS_FAIL $d or ${d}q exists"; exit 1; }
mkdir -p "${d}q" || exit 1
{ echo "# regress $tag: $id, snapshot $snap ($(head -n 1 "$snap/VERSION"))"
  for s in $chain; do echo "- rgr $s $tag"; done; } > "${d}q/regress.spec"
echo "REGRESS rundir $d"
"$f/common/queue.sh" "${d}q" "${d}q/regress.spec"
EOF
) ; echo "$out"
    [[ $out == *"QUEUE pid/pgid "* ]] || die "launch of $tag on $host"
    echo "REGRESS run $tag host $host snapshot $snap; check: regress.sh check $host $tag"
}

# the run's facts: snapshot VERSION, queue.state, the signoff step's GATE / VERDICT / SIGNOFF lines as the queue saved them
# and (prefix R) as the snapshot's signoff step gives them now on the run dir (R102: before, only the saved output was
# read, so a run dir changed after its signoff step, or a saved output that is not the verdict of the run dir, passed)
facts() {
    local host=$1 tag=$2 user
    name_ok "$host"; name_ok "$tag"
    user=$($ssh "$host" 'printf %s "$USER"') && name_ok "$user" || die "no remote user on $host"
    $ssh "$host" bash -s -- "'/tmp/$user/qc18bacc/rgr_$tag'" "'$tag'" << 'EOF'
set -u
snap=$1 tag=$2
[ -f "$snap/VERSION" ] || { echo "REGRESS_FAIL no snapshot $snap"; exit 1; }
d=$("$snap/qc18bacc/flow/blocks/rgr/run.sh" rundir "$tag") && q=$(cat "$d/queue.dir" 2> /dev/null) \
    || { echo "REGRESS_FAIL no queue of run dir $d"; exit 1; }
echo "V $(head -n 1 "$snap/VERSION")"
sed -n 's/^site_md5 /S /p' "$snap/VERSION"
grep '^init inputs ' "$d/summary.txt" 2> /dev/null | tail -n 1 | sed 's/^init inputs /I /'
sed 's/^/Q /' "$q/queue.state" || exit 1
# (an unfinished chain has no signoff output yet: the checks report it)
n=$(awk '$3 == "signoff" { print $1 }' "$q/queue.state")
[ -z "$n" ] || grep -h '^GATE \|^VERDICT \|^SIGNOFF ' "$q/q${n}_rgr_signoff.out" 2> /dev/null
"$snap/qc18bacc/flow/blocks/rgr/run.sh" signoff "$tag" 2>&1 | grep '^GATE \|^VERDICT \|^SIGNOFF ' | sed 's/^/R /'
exit 0
EOF
}
# the gate set of GATE lines on stdin: one line "gate <name> <corner ...>" per gate name, in verdict order
gates() { awk '$1 == "GATE" { if (!($2 in c)) o[n++] = $2; c[$2] = c[$2] " " $3 } END { for (i = 0; i < n; i++) print "gate " o[i] c[o[i]] }'; }

# the run is of the flow under test (R99; before, check compared ANY run with the checkout's reference): the tree of the
# snapshot's VERSION line "commit <c> tree <t>" has the paths deploy.sh archives (R100: qc18bacc/flow and flow/tsmc65) of
# <rev>, apart from the reference the run is compared with (ref writes it from the run, so it differs in the reviewed commit)
version() {   # version <VERSION line> <rev>
    local t want p f=() x=':(top,exclude)qc18bacc/flow/blocks/rgr/reference.txt'
    for p in $(bash "$here/deploy.sh" --paths); do f+=(":(top)$p"); done
    want=$(git -C "$here" rev-parse --verify --quiet "$2^{tree}" 2> /dev/null) || { echo "CHECK version FAIL '$2' is not a commit or tree"; return 1; }
    t=$(sed -n 's/^commit [0-9a-fnoe]* tree \([0-9a-f]\{40\}\)$/\1/p' <<< "$1")
    [ -n "$t" ] || { echo "CHECK version FAIL no 'commit <c> tree <t>' VERSION line: '$1'"; return 1; }
    git -C "$here" cat-file -e "$t^{tree}" 2> /dev/null || { echo "CHECK version FAIL run tree $t is not in this repository"; return 1; }
    if git -C "$here" diff --quiet "$want" "$t" -- "${f[@]}" "$x"; then
        echo "CHECK version PASS run tree ${t:0:12} = $2 (tree ${want:0:12}) in ${f[*]}"
    else
        echo "CHECK version FAIL run tree ${t:0:12} is not $2 (tree ${want:0:12}): ${f[*]} differ in"
        git -C "$here" diff --stat "$want" "$t" -- "${f[@]}" "$x" | head -n 20; return 1
    fi
}
# provenance outside the commit (R100), each equal to the reference's: the site manifest of the snapshot (VERSION
# site_md5 lines, common/deploy.sh) and the DC inputs of the run (summary.txt "init inputs" line, common/block.sh
# blk_inputs).  provenance <facts> <name> <fact key> <reference key>
provenance() {
    local a b
    a=$(grep "^$4 " "$ref" | LC_ALL=C sort); b=$(sed -n "s/^$3 /$4 /p" <<< "$1" | LC_ALL=C sort)
    if [ -z "$b" ]; then echo "CHECK $2 FAIL the run has no '$4' line"; return 1; fi
    if [ "$a" = "$b" ]; then echo "CHECK $2 PASS $(wc -l <<< "$b") '$4' line(s) = reference"; return 0; fi
    echo "CHECK $2 FAIL (< reference, > run; a deliberate change needs regress.sh ref + review):"
    diff <(echo "$a") <(echo "$b") | grep '^[<>]' | cut -c1-200 | head -n 20; return 1
}
# check <host> <run> <rev> [1] (1 = ref: everything but the comparison with the reference)
check() {
    local f bad=0 st v s g r o
    f=$(facts "$1" "$2") || { echo "$f"; die "no facts of run $2 on $1"; }
    [[ $f != *REGRESS_FAIL* ]] || { echo "$f"; die "no facts of run $2 on $1"; }
    # the verdict re-run on the run dir must be the signoff step's saved one; the checks below read the re-run
    o=$(grep '^GATE \|^VERDICT \|^SIGNOFF ' <<< "$f"); r=$(sed -n 's/^R //p' <<< "$f")
    if [ -n "$r" ] && [ "$r" = "$o" ]; then
        echo "CHECK verdict_rerun PASS $(grep -c '^GATE ' <<< "$r") GATE lines of the verdict re-run on the run dir = the signoff step's"
    else
        echo "CHECK verdict_rerun FAIL the verdict re-run on the run dir (>) is not the signoff step's (<):"
        diff <(echo "$o") <(echo "$r") | grep '^[<>]' | cut -c1-200 | head -n 20; bad=1
    fi
    f=$(grep -v '^GATE \|^VERDICT \|^SIGNOFF \|^R ' <<< "$f"; echo "$r")
    echo "REGRESS $2 on $1: $(sed -n 's/^V //p' <<< "$f")"
    version "$(sed -n 's/^V //p' <<< "$f")" "$3" || bad=1
    st=$(awk '$1 == "Q" { printf "%s:%s:%s ", $4, $6, $9 }' <<< "$f")
    [ "$st" = "$(for s in $CHAIN; do printf '%s:ok:0 ' "$s"; done)" ] \
        && echo "CHECK chain PASS $CHAIN all ok" || { echo "CHECK chain FAIL steps (step:status:rc) $st"; bad=1; }
    s=$(grep '^SIGNOFF ' <<< "$f" | tail -n 1); v=$(grep '^VERDICT ' <<< "$f" | tail -n 1)
    g=$(grep -c '^GATE .* \(FAIL\|MISSING\) ' <<< "$f")
    [[ $s == "SIGNOFF "*" PASS" ]] && [ "$g" = 0 ] && [[ $v == *" fail 0 missing 0; FAIL: none; MISSING: none;"* ]] \
        && echo "CHECK verdict PASS $v" || { echo "CHECK verdict FAIL '${s:-no SIGNOFF line}' gates FAIL / MISSING $g: ${v:-no VERDICT line}"; bad=1; }
    grep '^GATE .* \(FAIL\|MISSING\) ' <<< "$f" | cut -c1-160 | head -n 20
    if [ "${4:-0}" = 1 ]; then
        [ $bad = 0 ] || die "run $2 does not pass: no reference from it"
        grep -q '^S ' <<< "$f" && grep -q '^I ' <<< "$f" || die "run $2 has no site manifest or no 'init inputs' line: no reference from it"
        { echo "# Regression reference (common/regress.sh check): the site manifest of the snapshot (site_md5), the DC inputs of"
          echo "# the run (inputs: md5 of netlist, DC SDC, run.env), the verdict line and the gate set (gate name: sign-off corners,"
          echo "# '-' = block gate) of the run below; written by regress.sh ref, a change is a deliberate reference update"
          echo "# run $2 host $1 snapshot $(sed -n 's/^V //p' <<< "$f")"
          sed -n 's/^S /site_md5 /p; s/^I /inputs /p' <<< "$f"
          echo "$v"; grep '^GATE ' <<< "$f" | gates; } > "$ref"
        echo "REGRESS reference $ref from $2: $(grep -c '^gate ' "$ref") gate names"; return 0
    fi
    [ -f "$ref" ] || die "no reference $ref (regress.sh ref)"
    provenance "$f" site S site_md5 || bad=1
    provenance "$f" inputs I inputs || bad=1
    [ "$v" = "$(grep '^VERDICT ' "$ref")" ] && echo "CHECK verdict_line PASS = reference" \
        || { echo "CHECK verdict_line FAIL reference: $(grep '^VERDICT ' "$ref")"; bad=1; }
    if g=$(diff <(grep '^gate ' "$ref" | sort) <(grep '^GATE ' <<< "$f" | gates | sort)); then
        echo "CHECK gate_set PASS $(grep -c '^gate ' "$ref") gate names = reference"
    else
        echo "CHECK gate_set FAIL (< reference, > run $2; a checker change needs regress.sh ref + review):"
        echo "$g" | grep '^[<>]' | cut -c1-200 | head -n 60; bad=1
    fi
    [ $bad = 0 ] && echo "REGRESS $2 PASS" || echo "REGRESS $2 FAIL"
    return $bad
}

case $cmd in
run) run "$2" "$3" ;;
check) check "$2" "$3" "${4:-HEAD}" ;;
ref) check "$2" "$3" "${4:-HEAD}" 1 ;;
*) die "unknown command '$cmd' (run | check | ref)" ;;
esac
