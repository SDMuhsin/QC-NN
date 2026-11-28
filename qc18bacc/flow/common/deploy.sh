#!/usr/bin/env bash
# Immutable flow snapshot of ONE git commit on a build host (the regression runs from such snapshots, blocks/rgr):
#   qc18bacc/flow/common/deploy.sh <commit | tree-ish> <host>:<dir>
#   qc18bacc/flow/common/deploy.sh --paths      prints the repository paths a snapshot archives (common/regress.sh)
# Content: git archive of the tracked files of qc18bacc/flow and flow/tsmc65 (the shared kit / DC / PT layer every step
# runs: common/lib.tcl, common/tool.sh qc_tool, ...) at that commit, never the working tree, so uncommitted code cannot
# reach a run; + the host's untracked site files (flow/tsmc65/site: the kit-derived site.tcl, site.csh, pnr.tcl, ...,
# .gitignore; every file there the commit does not track) from QC_SITE_SRC = the host's flow/ (default
# /tmp/<remote user>/qc18bacc/f6/flow).  R100 [M] hunt on a06c97: the whole host flow/ was copied, tracked files included,
# so a run executed whatever lib.tcl / tool.sh the host held and VERSION named only the directory.
# VERSION: "commit <c> tree <t>", the site source, one "site_md5 <md5> <path>" line per site file (generic names only: a
# site file is <x>.<ext> of a tracked template <x>.example.<ext>) and (R115) one "kit_md5 <role> <md5>" line per kit file
# the flow reads by path (common/env.sh qb_kit_files, the one role table: tf, tlup_<corner>, lib_db_<corner>, lvs_deck,
# ...; keyed by role, the path is resolved on the host and recorded nowhere) (the site manifest, compared with
# blocks/rgr/reference.txt by regress.sh check; the kit-derived files themselves never leave the
# host) and the deploy time; MANIFEST.md5: md5 of every other file (md5sum -c format, relative paths).  Refuses an existing <dir>:
# the snapshot is staged in <dir>.part, verified against its MANIFEST on the host, made read-only and only then renamed
# to <dir>.  A tree id (e.g. git write-tree) is accepted as well and recorded as "tree" with no commit.
#   ssh command QC_SSH (default ssh); run from any directory of the repository checkout.
set -euo pipefail
PATHS="qc18bacc/flow flow/tsmc65"
die() { echo "DEPLOY_FAIL $*" >&2; exit 1; }
[ "${1:-}" != --paths ] || { echo "$PATHS"; exit 0; }
[ $# = 2 ] || die "usage: deploy.sh <commit | tree-ish> <host>:<dir> | --paths"
rev=$1 host=${2%%:*} dir=${2#*:}
[ "$host" != "$2" ] && [ -n "$host" ] || die "'$2' is not <host>:<dir>"
[[ $dir =~ ^/[A-Za-z0-9_./-]+$ && $dir != */ && $dir != *..* ]] || die "'$dir' is not an absolute path of [A-Za-z0-9_./-] without .. or a trailing /"
[[ ${QC_SITE_SRC:-/x} =~ ^/[A-Za-z0-9_./-]+$ ]] || die "QC_SITE_SRC '$QC_SITE_SRC' is not an absolute path of [A-Za-z0-9_./-]"
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
tree=$(git rev-parse --verify --quiet "$rev^{tree}" 2> /dev/null) || die "'$rev' is not a commit or tree"
if commit=$(git rev-parse --verify --quiet "$rev^{commit}" 2> /dev/null); then ver="commit $commit tree $tree"; else ver="commit none tree $tree"; fi
ssh=${QC_SSH:-ssh}
echo "DEPLOY $rev = $ver -> $host:$dir"
# 1. stage dir <dir>.part (refused when <dir> or the stage exists; removed again if the archive does not unpack)
git archive --format=tar "$tree" $PATHS | $ssh "$host" \
    "[ ! -e '$dir' ] && [ ! -e '$dir.part' ] || { echo 'DEPLOY_FAIL $dir or $dir.part exists'; exit 1; }
     mkdir -p \"\$(dirname '$dir')\" && mkdir '$dir.part' || exit 1
     tar xf - -C '$dir.part' || { rm -rf '$dir.part'; exit 1; }" || die "staging on $host"
# 2. site files, VERSION, MANIFEST, verify, read-only, rename; the stage is removed on any failure
$ssh "$host" bash -s -- "'$dir'" "'$ver'" "'${QC_SITE_SRC:-}'" << 'EOF' || die "snapshot on $host"   # (ssh joins the words: one quoted word each)
set -euo pipefail
d=$1 p=$1.part ver=$2 site=${3:-/tmp/$USER/qc18bacc/f6/flow}
trap 'if [ -d "$p" ]; then chmod -R u+w "$p"; rm -rf "$p"; fi' EXIT
s=flow/tsmc65/site
[ -f "$site/tsmc65/site/site.tcl" ] || { echo "DEPLOY_FAIL no site file $site/tsmc65/site/site.tcl"; exit 1; }
[ -d "$p/$s" ] || { echo "DEPLOY_FAIL the archive has no $s"; exit 1; }
# the untracked site files: every regular file of the host's site dir the archive does not have (a tracked one, e.g. a
# *.example.* template, comes from the commit only); their md5 = the site manifest of VERSION.  Generic names only (R115:
# the manifest goes into blocks/rgr/reference.txt): <x>.<ext> needs the tracked template <x>.example.<ext>
m=""
for f in "$site/tsmc65/site"/*; do
    [ -f "$f" ] && [ ! -e "$p/$s/${f##*/}" ] || continue
    n=${f##*/}; [[ $n == ?*.?* && -f $p/$s/${n%.*}.example.${n##*.} ]] \
        || { echo "DEPLOY_FAIL a site file of $site/tsmc65/site has no tracked <x>.example.<ext> template (not a generic name)"; exit 1; }
    cp -p "$f" "$p/$s/"
    m="${m}site_md5 $(md5sum < "$f" | cut -c1-32) $s/${f##*/}"$'\n'
done
[ -n "$m" ] || { echo "DEPLOY_FAIL no untracked site file in $site/tsmc65/site"; exit 1; }
# the kit files the flow reads by path (R115; round-16 hunt: TLU+, cell GDS, Calibre decks, layer map were in no record):
# common/env.sh qb_kit_files of the snapshot ("<role> <path>"), md5 taken here on the host, one kit_md5 line per role
k=$(bash -c '. "$1/qc18bacc/flow/common/env.sh" && qb_kit && qb_kit_files' _ "$p") && [ -n "$k" ] \
    || { echo "DEPLOY_FAIL no kit file table (common/env.sh qb_kit_files)"; exit 1; }
[ -z "$(cut -d' ' -f1 <<< "$k" | uniq -d)" ] || { echo "DEPLOY_FAIL a kit role twice: $(cut -d' ' -f1 <<< "$k" | uniq -d | tr '\n' ' ')"; exit 1; }
while read -r r f; do
    [[ $r =~ ^[a-z][a-z0-9_]*$ ]] && [ -f "$f" ] && [ -r "$f" ] || { echo "DEPLOY_FAIL kit role '$r': not a readable file"; exit 1; }
    m="${m}kit_md5 $r $(md5sum < "$f" | cut -c1-32)"$'\n'
done <<< "$k"
printf '%s\nsite %s:%s\n%sdeployed %s\n' "$ver" "$(hostname -s)" "$site" "$m" "$(date +%F_%T)" > "$p/VERSION"
cd "$p"
find . -type f ! -path ./MANIFEST.md5 -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' md5sum > MANIFEST.md5
md5sum --quiet -c MANIFEST.md5
# the site files of the snapshot are the ones its site manifest names
sed -n 's/^site_md5 \([0-9a-f]*\) \(.*\)$/\1  \2/p' VERSION | md5sum --quiet -c
chmod -R a-w .
cd /; [ ! -e "$d" ] || { echo "DEPLOY_FAIL $d appeared during the deploy (stage removed)"; exit 1; }
mv -T "$p" "$d"
echo "DEPLOY_OK $(hostname -s):$d $(head -n 1 "$d/VERSION") files $(wc -l < "$d/MANIFEST.md5") manifest $(md5sum < "$d/MANIFEST.md5" | cut -c1-12) site files $(grep -c '^site_md5 ' "$d/VERSION") kit roles $(grep -c '^kit_md5 ' "$d/VERSION")"
EOF
