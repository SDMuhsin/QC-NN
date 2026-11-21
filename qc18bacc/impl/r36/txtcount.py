# R36 KLayout: count text labels per layer/datatype in the top cell of a GDS.  klayout -b -r txtcount.py -rd gds=<f>
import pya, collections
ly = pya.Layout(); ly.read(gds); top = ly.top_cell(); c = collections.Counter(); ex = {}
for li in ly.layer_indexes():
    info = ly.get_info(li)
    for sh in top.shapes(li).each():
        if sh.is_text(): c[(info.layer, info.datatype)] += 1; ex.setdefault((info.layer, info.datatype), sh.text_string)
for k in sorted(c): print('TXT layer %d/%d n %d e.g. %s' % (k[0], k[1], c[k], ex[k]))
