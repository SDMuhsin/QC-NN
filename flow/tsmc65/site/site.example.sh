# Server link settings for flow/tsmc65/sync.sh.  Copy to site.sh (git-ignored) and fill in every <PLACEHOLDER>.
QC_HOST=${QC_HOST:-<SSH_HOST_ALIAS>}       # ssh alias of the build server; override per call: QC_HOST=other sync.sh ...
QC_SSH=${QC_SSH:-ssh}                       # ssh command (may be wrapped, e.g. with SSH_ASKPASS settings)
QC_CHECKOUT=<CLONE_DIR>                     # git clone on the server, relative to the remote home
QC_WIP=${QC_WIP:-<WORK_DIR>}                        # pre-push work tree on the server (rsync copy), relative to the remote home
QC_WIP_DIRS=${QC_WIP_DIRS:-"flow"}              # top-level repo dirs copied by `sync.sh wip`
