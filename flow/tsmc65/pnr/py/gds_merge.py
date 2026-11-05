# KLayout batch script: routed DEF + LEF + cell GDS -> merged GDS.
#   klayout -b -r gds_merge.py -rd def_in=<x.def> -rd lefs="<tech.lef> [macro.lef ...]" -rd gds="<cells.gds> [...]"
#           -rd layer_map=<klayout.map> -rd out=<x.gds>
# Cells found in the GDS files replace their LEF abstracts; macros without GDS (the SRAMs) keep the LEF
# abstract geometry and are listed as "no GDS".
import re
import pya

opt = pya.LoadLayoutOptions()
cfg = opt.lefdef_config
cfg.map_file = layer_map
m = re.search(r'UNITS\s+DISTANCE\s+MICRONS\s+(\d+)', open(def_in).read(4096))
if m:
    cfg.dbu = 1.0 / int(m.group(1))
cfg.lef_files = lefs.split()
cfg.read_lef_with_def = False
cfg.macro_resolution_mode = 0
cfg.macro_layout_files = gds.split()
opt.lefdef_config = cfg
ly = pya.Layout()
ly.read(def_in, opt)
top = ly.top_cell()
missing = sorted(set(ly.cell(i).name for i in top.each_child_cell() if ly.cell(i).is_ghost_cell() or ly.cell(i).bbox().empty()))
ly.write(out)
print('gds_merge: top %s cells %d no GDS: %s' % (top.name, ly.cells(), ' '.join(missing) or 'none'))
