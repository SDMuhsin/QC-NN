# R45 probe (klayout python): layers / shapes of given cells in a GDS.  usage: python gdscell45.py <gds> CELL [CELL...]
import sys, klayout.db as db
ly = db.Layout(); ly.read(sys.argv[1])
for cn in sys.argv[2:]:
    c = ly.cell(cn)
    if c is None: print(cn, 'missing'); continue
    for li in ly.layer_indexes():
        n = c.shapes(li).size()
        if n:
            info = ly.get_info(li); bb = c.shapes(li).each().__next__().bbox() if n else None
            print(cn, '%d/%d' % (info.layer, info.datatype), n, 'first', bb.to_s() if bb else '')
# env R45_AT="x y r" (um): top-cell shapes (all layers, flattened 1 level) touching that box
import os
if os.environ.get('R45_AT'):
    x, y, r = map(float, os.environ['R45_AT'].split())
    top = ly.top_cell(); u = ly.dbu
    box = db.Box(int((x - r) / u), int((y - r) / u), int((x + r) / u), int((y + r) / u))
    for li in ly.layer_indexes():
        info = ly.get_info(li)
        it = top.begin_shapes_rec_touching(li, box)
        while not it.at_end():
            sh = it.shape(); print('AT %d/%d' % (info.layer, info.datatype), it.cell().name, sh.bbox().transformed(it.trans()).to_s()); it.next()
