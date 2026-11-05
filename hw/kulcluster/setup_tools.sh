#!/usr/bin/env bash
# Fetch the tools needed to (re)generate the KUL cluster RTL and run its standalone test.
# Everything goes into $QCNN/tools (git-ignored). Idempotent.
set -euo pipefail
KUL_NO_VLT=1 source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
T=$QCNN/tools; mkdir -p $T/dl
fetch() { [ -f "$T/dl/$1" ] || curl -sSL -o "$T/dl/$1" "$2"; }
if [ ! -x $T/jdk/bin/java ]; then   # Chisel 6 / sbt need a JDK (snax container: openjdk 11)
  fetch jdk11.tar.gz "https://api.adoptium.net/v3/binary/latest/11/ga/linux/x64/jdk/hotspot/normal/eclipse"
  mkdir -p $T/jdk && tar -C $T/jdk --strip-components=1 -xzf $T/dl/jdk11.tar.gz; fi
if [ ! -x $T/sbt/bin/sbt ]; then    # launcher; project pins sbt 1.9.6 itself
  fetch sbt.tgz https://github.com/sbt/sbt/releases/download/v1.10.2/sbt-1.10.2.tgz
  mkdir -p $T/sbt && tar -C $T/sbt --strip-components=1 -xzf $T/dl/sbt.tgz; fi
if [ ! -x $T/morty/bin/morty ]; then
  fetch morty.tgz https://github.com/pulp-platform/morty/releases/download/v0.9.0/morty-ubuntu.22.04-x86_64.tar.gz
  mkdir -p $T/morty/bin && tar -C $T/morty/bin -xzf $T/dl/morty.tgz morty; fi
if [ ! -x $T/llvm17/bin/clang ]; then   # only for the standalone SW build
  fetch llvm17.tar.xz https://github.com/llvm/llvm-project/releases/download/llvmorg-17.0.6/clang+llvm-17.0.6-x86_64-linux-gnu-ubuntu-22.04.tar.xz
  d=clang+llvm-17.0.6-x86_64-linux-gnu-ubuntu-22.04
  mkdir -p $T/llvm17 && tar -C $T/llvm17 --strip-components=1 -xJf $T/dl/llvm17.tar.xz $d/bin $d/lib/clang; fi
if [ ! -x $T/stubbin/dtc ]; then   # fesvr configure only checks that dtc exists
  mkdir -p $T/stubbin; printf '#!/bin/sh\necho "dtc stub" >&2\nexit 1\n' > $T/stubbin/dtc; chmod +x $T/stubbin/dtc; fi
if [ ! -x $T/snax-venv/bin/python ] || ! $T/snax-venv/bin/python -c 'import hjson,mako,jsonref' 2>/dev/null; then
  python3 -m venv $T/snax-venv
  $T/snax-venv/bin/pip install -q -r "$KUL_DIR/python-requirements.txt"; fi
[ -x $T/bender/bin/bender ] || { echo "bender missing at $T/bender/bin (see top-level setup)"; exit 1; }
echo "tools OK"
