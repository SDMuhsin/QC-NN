# R38: macro LEF abstracts -> GDS cells (pins on the drawing layer + pin labels on the text layer, OBS on 255/<n>, via the
# same KLayout layer map as the DEF merge), for macros with no layout (front-end-licensed SRAMs).  Used as extra
# macro_layout_files in the DEF merge so the SRAM pins exist for LVS BOX and DRC.
#   python3 klrun.py -b -r lef2gds.py -rd lefs="<tech.lef> <m1.lef> ..." -rd layer_map=<kl.map> -rd out=<x.gds>
def opts():
    opt = pya.LoadLayoutOptions(); cfg = opt.lefdef_config
    cfg.map_file = layer_map; cfg.dbu = 0.001; cfg.macro_resolution_mode = 1; cfg.lef_files = [lefs.split()[0]]
    opt.lefdef_config = cfg
    return opt
ly = pya.Layout(); ly.dbu = 0.001
for f in lefs.split()[1:]:
    tmp = pya.Layout(); tmp.read(f, opts())
    for c in tmp.each_cell():
        if not c.bbox().empty() and ("MACRO " + c.name + "\n") in open(f).read():
            n = ly.create_cell(c.name); n.copy_tree(c)
            # opt-in QB38 stack=1: LEF pins drawn on M1 / M2 / M3 at one spot have no vias in the abstract -> Calibre
            # sees one net per layer ("Open circuit - same name on different nets").  Add the overlap of adjacent pin
            # layers as a cut (LVS connectivity only; the SRAM region is not DRC-checked anyway)
            if globals().get('stack', '0') == '1':
                for (a, v, b) in ((31, 51, 32), (32, 52, 33), (33, 53, 34), (34, 54, 35)):
                    la = ly.find_layer(a, 0); lb = ly.find_layer(b, 0)
                    if la is None or lb is None: continue
                    ov = pya.Region(n.begin_shapes_rec(la)) & pya.Region(n.begin_shapes_rec(lb))
                    if not ov.is_empty():
                        n.shapes(ly.layer(v, 0)).insert(ov); print('LEF2GDS', c.name, 'stack cuts %d/%d->%d/%d: %d' % (a, 0, b, 0, ov.count()))
            print('LEF2GDS', c.name, 'bbox', c.dbbox(), 'shapes', sum(c.shapes(li).size() for li in tmp.layer_indexes()))
ly.write(out)
