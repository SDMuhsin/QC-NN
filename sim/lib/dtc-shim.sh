#!/bin/sh
# Configure-time shim: fesvr's ./configure requires dtc, the snitch TB never runs it.
echo "dtc shim: not available" >&2
exit 1
