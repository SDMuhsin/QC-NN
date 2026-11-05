# Memory-compiler settings for flow/tsmc65/sram/mc_gen.sh.  Copy to sram.sh (git-ignored), fill in every <PLACEHOLDER>.
QC_MC_KIT=<MEMORY_COMPILER_DIR>             # directory holding the memory compilers (one sub-dir per compiler)
QC_MC_JRE=<JAVA8_JRE_DIR>                   # a Java 8 runtime (jre dir) of the build host
QC_MC_SCRATCH=/tmp/$USER/qcnn/mc_scratch    # host-local scratch for the staged compilers (not NFS)
QC_MC_OUT=/tmp/$USER/qcnn/macros            # generated views (host-local; never the NFS home)
QC_MC_CORNERS=<C_SS>,<C_TT>,<C_FF_COLD>,<C_FF_HOT>   # exactly four characterisation corners, in this order
QC_MC_LC_SETUP=<LIBRARY_COMPILER_SETUP_CSH>          # tcsh setup of Library Compiler (lc_shell, .lib -> .db)
