# Tool environment template (tcsh), sourced by every flow tool run on the server.  Copy to site.csh (git-ignored).
source <DC_SETUP_CSH>  >& /dev/null
source <PT_SETUP_CSH>  >& /dev/null
source <VCS_SETUP_CSH> >& /dev/null
setenv QC_KIT    <STDCELL_KIT_ROOT>              # read by site.tcl
setenv QC_CELL_V <STDCELL_VERILOG_MODELS>        # cell models for gate-level simulation (sim/run_vcs.sh, QC_GLS=1)
