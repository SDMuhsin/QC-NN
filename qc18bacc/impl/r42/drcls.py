#!/usr/bin/env python3
"""R42: DR marker report -> R41 cause bins (a halo strip, b off-grid s_q / t2_s pins, c u_ds box, d rest).  drcls.py <drc.rpt>"""
import sys,re,collections
t=open(sys.argv[1]).read().split("violation type:")[1:]
cls=collections.Counter(); oth=collections.Counter(); onets=collections.Counter(); det=collections.Counter()
for v in t:
    m=re.search(r"bbox = \(\s*([\d.]+),\s*([\d.]+)\s*\) - \(\s*([\d.]+),\s*([\d.]+)\s*\) on Layer (\S+)",v)
    x,y,l=float(m.group(1)),float(m.group(2)),m.group(5); ty=v.split("\n")[0].strip()
    src=re.search(r"srcs:(.*)",v).group(1)
    if 740<=x<=1600 and 1950.8<=y<=2010.8: c="a_halo"
    elif ("s_q" in src and l in("M6","VIA5","VIA6","M5","M7")) or ("t2_s" in src and l in ("M8","VIA7","VIA8","M7","M9")): c="b_offgrid"
    elif x<500 and 5700<y<6800: c="c_uds"
    else:
        c="d_other"; oth[(int(x//100)*100,int(y//100)*100)]+=1
        for n in re.findall(r"net:(\S+)",src): onets[re.sub(r"\d+","#",n)]+=1
        det[(ty,l)]+=1
    cls[c]+=1
print("TOTAL",len(t),dict(cls)); print("D_TYPES",det.most_common(6)); print("D_BINS",oth.most_common(5)); print("D_NETS",onets.most_common(6))
