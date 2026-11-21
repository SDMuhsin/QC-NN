# R38: shape / text count per layer of one cell (not recursive).  python3 klrun.py -b -r cellstat.py -rd gds=.. -rd cell=..
ly = pya.Layout(); ly.read(gds); c = ly.cell(cell)
for li in ly.layer_indexes():
    sh = c.shapes(li); n = sh.size()
    if n:
        nt = sum(1 for s in sh.each() if s.is_text())
        print('CELLSTAT %s %s shapes %d texts %d' % (cell, ly.get_info(li), n, nt))
print('CELLSTAT bbox', c.dbbox())
