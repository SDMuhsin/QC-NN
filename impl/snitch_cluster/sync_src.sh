#!/usr/bin/env bash
# Copy the design sources to the server work tree (the tree of `flow/tsmc65/sync.sh wip`), run locally:
#   impl/snitch_cluster/sync_src.sh            (QC_HOST / QC_SSH / QC_WIP from flow/tsmc65/site/site.sh)
# 1. `sync.sh wip` for flow/, hw/ and impl/ (QC_WIP_DIRS);
# 2. the source files named by flist/*.f (chimera: third_party/chimera deps; fp: the sim workspace
#    build/sim/ws/chimera_fp) plus every include directory, mirrored at the same repo-relative paths (about 20 MB; the
#    bender checkouts themselves are over 1 GB).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
. "$REPO/flow/tsmc65/site/site.sh"
QC_WIP_DIRS="flow hw impl" "$REPO/flow/tsmc65/sync.sh" wip
list=$(mktemp)
trap 'rm -f "$list"' EXIT
cat "$HERE"/flist/*.f | sed -n 's#^\$QC_ROOT/##p' > "$list"
cat "$HERE"/flist/*.f | sed -n 's#^+incdir+\$QC_ROOT/##p' | sort -u | while read -r d; do
    (cd "$REPO" && find "$d" -type f)
done >> "$list"
rsync -rltpR -e "$QC_SSH" --files-from="$list" "$REPO/" "$QC_HOST:$QC_WIP/"
echo "sources synced: $(wc -l < "$list") files -> $QC_HOST:~/$QC_WIP"
