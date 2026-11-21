# R36 KLayout probe: text labels (top cell, flattened) on layer L/D whose string matches S (case-insensitive) and the
# drawing shapes of layer ML/MD under each label.  klayout -b -r probe_txt.py -rd gds=.. -rd s=A_FIRST -rd l=132 -rd ml=32
import pya
ly = pya.Layout(); ly.read(gds); top = ly.top_cell(); d = ly.dbu
li = ly.find_layer(int(l), int(globals().get('dt', 0))); mi = ly.find_layer(int(ml), int(globals().get('md', 0)))
it = top.begin_shapes_rec(li); n = 0
while not it.at_end():
    sh = it.shape()
    if sh.is_text() and sh.text_string.upper() == s.upper():
        t = sh.text.transformed(it.trans()); p = t.trans.disp
        box = pya.Box(p.x - 1, p.y - 1, p.x + 1, p.y + 1)
        m = 0; it2 = top.begin_shapes_rec_touching(mi, box)
        while not it2.at_end(): m += 1; it2.next()
        print('TXT %s at %.3f %.3f metal_shapes_under %d' % (sh.text_string, p.x * d, p.y * d, m)); n += 1
    it.next()
print('found', n)
