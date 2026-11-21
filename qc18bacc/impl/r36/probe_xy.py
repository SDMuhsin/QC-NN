# R36 KLayout probe: shapes (flattened) of layers M1 31/0, VIA1 51/0, M2 32/0 within +-r um of (x, y) in GDS top cell.
#   klayout -b -r probe_xy.py -rd gds=<f> -rd x=<um> -rd y=<um> [-rd r=0.6]
import pya
ly = pya.Layout(); ly.read(gds); top = ly.top_cell(); d = ly.dbu
R = float(globals().get('r', 0.6)); X = float(x); Y = float(y)
box = pya.Box(int((X - R) / d), int((Y - R) / d), int((X + R) / d), int((Y + R) / d))
for nm, (l, dt) in [(s.split(':')[0], tuple(map(int, s.split(':')[1].split('/')))) for s in globals().get('layers', 'M1:31/0 VIA1:51/0 M2:32/0').split()]:
    li = ly.find_layer(l, dt)
    if li is None: print(nm, 'absent'); continue
    it = top.begin_shapes_rec_touching(li, box)
    n = 0
    while not it.at_end():
        b = it.shape().bbox().transformed(it.trans())
        print('%s %.3f %.3f %.3f %.3f in %s' % (nm, b.left * d, b.bottom * d, b.right * d, b.top * d, ly.cell(it.cell_index()).name)); n += 1
        it.next()
    print(nm, 'n', n)
