#!/usr/bin/env bash
# impl/snitch_cluster/summarize.sh <syn_run_dir> <out_dir>: short result files (see summarize.py).
exec python3 -I "$(cd "$(dirname "$0")" && pwd)/summarize.py" "$@"
