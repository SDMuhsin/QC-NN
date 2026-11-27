# Sourced (bash): KLayout batch runs of the Calibre sign-off (results/r38.md; klayout Python wheel $QC_TOOLS/kl_py via
# klrun.py, no klayout binary on tau6).
#   kl_run <script.py> [-rd k=v ...]   klayout -b -r <script.py> ... ; exit status of the script
_kl_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_kl_tools=${QC_TOOLS:-/tmp/$USER/tools}
kl_run() { PYTHONPATH=$_kl_tools/kl_py${PYTHONPATH:+:$PYTHONPATH} "$_kl_tools/env/bin/python3" "$_kl_here/klrun.py" -b -r "$@"; }
