# R68: Calibre dummy metal (cal.sh fill: DM.gds, cell <top>_DM placed at 0 0 in <top>) -> DEF FILLS section, read by ICC2
# (flow/icc2/extract.tcl, read_def -include fills) so the extraction sees the fill the sign-off GDS carries.  Every shape
# of GDS layer 30 + i (any datatype: kit dummy datatypes 1 = DMi, 7 = RMi) becomes one FILLS statement on layer Mi
# (tsmcn65 tf: metal Mi = GDS layer 30 + i, flow/icc2/outputs.tcl); boxes as RECT, other shapes as POLYGON.
#   kl_run fill_def.py -rd gds=<DM.gds> -rd design=<top> -rd out=<fill.def>     (signoff/calibre/kl.sh)
import sys
ly = pya.Layout(); ly.read(gds)                                   # noqa: F821 (klrun.py globals)
top = ly.top_cells()
if len(top) != 1: sys.exit(f"fill_def: {len(top)} top cells in {gds}")
u = 1000                                                          # DEF database units per micron
k = ly.dbu * u
recs, n = [], {}
for li in ly.layer_indexes():
    info = ly.get_info(li)
    if not 31 <= info.layer <= 39: sys.exit(f"fill_def: unexpected layer {info} in {gds}")
    lay = f"M{info.layer - 30}"
    it = top[0].begin_shapes_rec(li)
    while not it.at_end():
        s = it.shape()
        if s.is_box() or s.is_polygon() or s.is_path():
            p = s.polygon.transformed(it.trans())
            if p.is_box():
                b = p.bbox()
                recs.append(f"- LAYER {lay} RECT ( {round(b.left * k)} {round(b.bottom * k)} ) ( {round(b.right * k)} {round(b.top * k)} ) ;")
            else:
                pts = " ".join(f"( {round(q.x * k)} {round(q.y * k)} )" for q in p.each_point_hull())
                recs.append(f"- LAYER {lay} POLYGON {pts} ;")
            n[lay] = n.get(lay, 0) + 1
        it.next()
with open(out, "w") as f:                                         # noqa: F821
    f.write(f'VERSION 5.8 ;\nDIVIDERCHAR "/" ;\nBUSBITCHARS "[]" ;\nDESIGN {design} ;\nUNITS DISTANCE MICRONS {u} ;\n')  # noqa: F821
    f.write(f"FILLS {len(recs)} ;\n" + "\n".join(recs) + "\nEND FILLS\nEND DESIGN\n")
print("FILL_DEF", len(recs), "shapes", " ".join(f"{l} {n[l]}" for l in sorted(n)), "->", out)  # noqa: F821
