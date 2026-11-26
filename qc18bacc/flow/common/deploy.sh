#!/usr/bin/env bash
# Immutable flow snapshot of ONE git commit on a build host (the regression runs from such snapshots, blocks/rgr):
#   qc18bacc/flow/common/deploy.sh <commit | tree-ish> <host>:<dir>
# Content: git archive of qc18bacc/flow at that commit (never the working tree, so uncommitted code cannot reach a run)
# + the host's flow/ (flow/tsmc65 with its untracked site files; QC_SITE_SRC = its path on the host, default
# /tmp/<remote user>/qc18bacc/f6/flow) copied as flow/; VERSION (the commit, its tree, the site source) and MANIFEST.md5 (md5 of
# every other file, md5sum -c format, relative paths).  Refuses an existing <dir>: the snapshot is staged in <dir>.part,
# verified against its MANIFEST on the host, made read-only and only then renamed to <dir>.  A tree id (e.g. git
# write-tree) is accepted as well and recorded as "tree" with no commit.
#   ssh command QC_SSH (default ssh); run from any directory of the repository checkout.
set -euo pipefail
die() { echo "DEPLOY_FAIL $*" >&2; exit 1; }
[ $# = 2 ] || die "usage: deploy.sh <commit | tree-ish> <host>:<dir>"
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
git archive --format=tar "$tree" qc18bacc/flow | $ssh "$host" \
    "[ ! -e '$dir' ] && [ ! -e '$dir.part' ] || { echo 'DEPLOY_FAIL $dir or $dir.part exists'; exit 1; }
     mkdir -p \"\$(dirname '$dir')\" && mkdir '$dir.part' || exit 1
     tar xf - -C '$dir.part' || { rm -rf '$dir.part'; exit 1; }" || die "staging on $host"
# 2. site layer, VERSION, MANIFEST, verify, read-only, rename; the stage is removed on any failure
$ssh "$host" bash -s -- "'$dir'" "'$ver'" "'${QC_SITE_SRC:-}'" << 'EOF' || die "snapshot on $host"   # (ssh joins the words: one quoted word each)
set -euo pipefail
d=$1 p=$1.part ver=$2 site=${3:-/tmp/$USER/qc18bacc/f6/flow}
trap 'if [ -d "$p" ]; then chmod -R u+w "$p"; rm -rf "$p"; fi' EXIT
[ -f "$site/tsmc65/site/site.tcl" ] || { echo "DEPLOY_FAIL no site layer $site/tsmc65/site/site.tcl"; exit 1; }
cp -a "$site" "$p/flow"
printf '%s\nsite %s:%s\ndeployed %s\n' "$ver" "$(hostname -s)" "$site" "$(date +%F_%T)" > "$p/VERSION"
cd "$p"
find . -type f ! -path ./MANIFEST.md5 -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' md5sum > MANIFEST.md5
md5sum --quiet -c MANIFEST.md5
chmod -R a-w .
cd /; [ ! -e "$d" ] || { echo "DEPLOY_FAIL $d appeared during the deploy (stage removed)"; exit 1; }
mv -T "$p" "$d"
echo "DEPLOY_OK $(hostname -s):$d $(head -n 1 "$d/VERSION") files $(wc -l < "$d/MANIFEST.md5") manifest $(md5sum < "$d/MANIFEST.md5" | cut -c1-12)"
EOF
