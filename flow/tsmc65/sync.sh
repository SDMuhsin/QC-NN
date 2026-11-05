#!/usr/bin/env bash
# Local <-> build-server link of the TSMC-65 flow (settings: git-ignored site/site.sh, template site/site.example.sh).
# The server is chosen by QC_HOST (default in site.sh), e.g.  QC_HOST=tau5 flow/tsmc65/sync.sh run '...'.
# Code normally reaches the server through git (push locally, then `sync.sh pull`).  To try changes before a push,
# `sync.sh wip` rsyncs the repo's QC_WIP_DIRS to a separate work tree and QC_TREE=wip runs there.
#   sync.sh pull           git pull --ff-only in the server checkout (QC_CHECKOUT)
#   sync.sh wip            rsync QC_WIP_DIRS (default: flow, site files included) to the work tree (QC_WIP)
#   sync.sh site           copy the real site files to the selected tree (they are not in git)
#   sync.sh run '<cmd>'    run a shell command at the repo root of the selected tree
#   sync.sh fetch <path>   copy <path> (relative to the remote repo root, e.g. build/tsmc65/syn/x/summary.txt)
#                          to flow/tsmc65/results/
#   sync.sh tree           print the selected remote tree
set -eu
FLOW=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$FLOW/../.." && pwd)
[ -f "$FLOW/site/site.sh" ] || { echo "missing $FLOW/site/site.sh (template site/site.example.sh)"; exit 1; }
. "$FLOW/site/site.sh"
case "${QC_TREE:-checkout}" in
    wip) TREE=$QC_WIP ;;
    *)   TREE=$QC_CHECKOUT ;;
esac
remote() { $QC_SSH "$QC_HOST" "$@"; }
RS() { rsync -rltp -e "$QC_SSH" "$@"; }
case "${1:-}" in
pull)  remote "cd ~/$QC_CHECKOUT && git pull -q --ff-only && git log -1 --format='%h %s'" ;;
wip)   remote "mkdir -p ~/$QC_WIP"
       for d in ${QC_WIP_DIRS:-flow}; do
           RS --delete --exclude results --exclude build "$REPO/$d" "$QC_HOST:$QC_WIP/"
       done
       echo "wip tree updated: $QC_HOST:~/$QC_WIP" ;;
site)  RS --exclude '*.example.*' "$FLOW/site/" "$QC_HOST:$TREE/flow/tsmc65/site/"
       echo "site files copied to $QC_HOST:~/$TREE" ;;
run)   remote "cd ~/$TREE && ${2:?command}" ;;
fetch) mkdir -p "$FLOW/results"; RS "$QC_HOST:$TREE/${2:?path}" "$FLOW/results/"; ls "$FLOW/results" ;;
tree)  echo "$QC_HOST:~/$TREE" ;;
*)     sed -n '2,13p' "$0"; exit 1 ;;
esac
