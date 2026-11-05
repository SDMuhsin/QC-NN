#!/usr/bin/env bash
# Install OpenROAD and KLayout without root, on host-local disk (run on the server):
#   flow/tsmc65/pnr/install_openroad.sh [prefix=/tmp/$USER/tools]
# A static micromamba binary creates two conda envs (the NFS home is never touched: root prefix and package cache
# are under <prefix>):
#   <prefix>/env  openroad from litex-hub (+ pkgs/main for its libboost 1.73)   tested: 2.0-12381-g01bba3695 (Feb 2024)
#   <prefix>/kl   klayout from conda-forge (separate env: its Qt pins clash with openroad's)   tested: 0.30.12
# Plain `-c litex-hub -c conda-forge` only resolves a March-2022 openroad (2.0_3175), hence pkgs/main.
# Idempotent; ~4 GB, ~3 min.  pnr/run_pnr.sh finds the tools via QC_TOOLS (default /tmp/$USER/tools).
set -eu
P=${1:-/tmp/$USER/tools}
mkdir -p "$P/bin"
export MAMBA_ROOT_PREFIX=$P/mamba CONDA_PKGS_DIRS=$P/mamba/pkgs
MM=$P/bin/micromamba
[ -x "$MM" ] || curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj -C "$P" bin/micromamba
"$MM" --version
[ -x "$P/env/bin/openroad" ] || "$MM" create -y -p "$P/env" -c litex-hub -c defaults --override-channels \
    "openroad${QC_OR_VER:->=2.0_10000}"
[ -x "$P/kl/bin/klayout" ] || "$MM" create -y -p "$P/kl" -c conda-forge --override-channels klayout \
    || echo "klayout install failed (GDS merge disabled)"
{ echo "openroad $("$P/env/bin/openroad" -version)"; "$P/kl/bin/klayout" -v 2>/dev/null || true; } | tee "$P/versions.txt"
