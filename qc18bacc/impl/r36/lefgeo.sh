#!/usr/bin/env bash
# R36: md5 / counts of a block LEF's geometry on the given layers (PIN rects with pin name, OBS rects), for "did the
# block's top-visible geometry change" checks between two abstract versions.   lefgeo.sh <lef> [layers "M7 M8 M9"]
awk -v L="${2:-M7 M8 M9}" 'BEGIN{n=split(L,a," "); for(i=1;i<=n;i++) k[a[i]]=1}
  /^  PIN /{pn=$2; o=0} /^  OBS/{o=1; pn="OBS"} /LAYER/{l=$2}
  /RECT/{ if (l in k) print (o?"O":"P"), pn, l, $2, $3, $4, $5 }' "$1" | sort > "$1.geo"
echo "LEFGEO $1 $(wc -l < "$1.geo") rects md5 $(md5sum < "$1.geo" | cut -c1-12)"
