#!/bin/sh
# Remote stand-in for bender (Questa host has no bender/deps database).
# `bender script vsim ...` replays the compile script generated locally by
# build_hw.sh (with ROOT rewritten to the remote path); other queries
# (e.g. `script flist` for make prerequisites) return nothing.
case "$*" in
  "script vsim"*) cat "${BENDER_REPLAY_TCL:?}" ;;
  *) : ;;
esac
