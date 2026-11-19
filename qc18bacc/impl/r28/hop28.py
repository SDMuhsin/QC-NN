# R28 (results/r28.md): opt-in ECO for a two-net crossing short DRT left on a lower layer (e.g. h125 M2 net243529 x
# net257073).  The named net's vertical segment at x crossing y0 is re-encoded as: its layer -> <via> at y0 -> the via's
# other layer to y1 -> <via> back, the rest of the wire op-for-op (PATH / POINT / POINT_EXT / VIA / TECH_VIA /
# RECT / ITERM / BTERM; anything else aborts).  On tau (odb Python):
#   openroad -python -exit hop28.py   with QB28_DB <in.odb> QB28_OUT <ops.txt> QB28_HOP "net x y0 y1 via" (dbu);
#   then eco28.sh with QB28_HOP_OPS "<net> <ops.txt>" re-encodes the net's wire from ops.txt
import os, sys
import odb
D = odb.dbWireDecoder
hv = os.environ["QB28_HOP"].split(); net_n = hv[0]
if len(hv) == 5: hx, y0, y1, vname = int(hv[1]), int(hv[2]), int(hv[3]), hv[4]
else: hx, y0, y1, vname = 0, 0, 0, "VIA23_1cut"
db = odb.dbDatabase.create(); odb.read_db(db, os.environ["QB28_DB"])
blk = db.getChip().getBlock(); tech = db.getTech(); via = tech.findVia(vname); net = blk.findNet(net_n)
w = net.getWire()
# getRect() / the POINT_EXT extension take C++ reference outputs (not callable from Python / Tcl): read the RECT
# deltas and point extensions from printWire instead
tmp = os.environ.get("QB28_TMP", "r28_hop_pw.txt"); sys.stdout.flush(); fd = os.dup(1); f = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
import ctypes; libc = ctypes.CDLL(None)
os.dup2(f, 1); w.printWire(); libc.fflush(None); sys.stdout.flush(); os.dup2(fd, 1); os.close(f)
import re
L = [l.split() for l in open(tmp)]; rects = []
for i, l in enumerate(L):
    if "WOP_RECT" in l:
        rects.append([int(l[-1])] + [int(L[i + j][-1]) for j in (1, 2, 3)])
exts = [int(l[-1]) for i, l in enumerate(L) if "WOP_OPERAND" in l and i > 0 and ("WOP_X" in L[i - 1] or "WOP_Y" in L[i - 1])]
d = D(); d.begin(w); ops = []
while True:
    op = d.next()
    if op == D.END_DECODE: break
    if op == D.PATH: ops.append(["PATH", d.getLayer(), d.getWireType()])
    elif op == D.POINT: ops.append(["PT"] + list(d.getPoint()))
    elif op == D.POINT_EXT: ops.append(["PTX"] + list(d.getPoint())[:2] + [exts.pop(0)])
    elif op == D.VIA: ops.append(["VIA", d.getVia()])
    elif op == D.TECH_VIA: ops.append(["TVIA", d.getTechVia()])
    elif op == D.RECT: ops.append(["RECT"] + rects.pop(0))
    elif op == D.ITERM: ops.append(["ITERM", d.getITerm()])
    elif op == D.BTERM: ops.append(["BTERM", d.getBTerm()])
    else: sys.exit("R28_HOP unsupported opcode %d" % op)
if os.environ.get("QB28_SEG"):
    # opt-in QB28_SEG "xa ya xb yb x1 y1 x2 y2 ...": replace the 2-point PATH (xa,ya)-(xb,yb) by the polyline x1 y1 x2 y2 ...
    # on the same layer (e.g. move a segment off a wide PG shape); QB28_HOP then only names the net
    v = [int(x) for x in os.environ["QB28_SEG"].split()]; k = -1
    for i in range(len(ops) - 2):
        a, b, c = ops[i], ops[i + 1], ops[i + 2]
        if a[0] == "PATH" and b[0] == "PT" and c[0] == "PT" and b[1:3] == v[0:2] and c[1:3] == v[2:4]: k = i; break
    if k < 0: sys.exit("R28_SEG segment not found")
    pts = v[4:]; ya, yb = v[1], v[3]; y0 = y1 = 0
    rep = []
    for j in range(0, len(pts) - 2, 2):
        rep += [["PATH", ops[k][1], ops[k][2]], ["PT", pts[j], pts[j + 1]], ["PT", pts[j + 2], pts[j + 3]]]
    ops[k:k + 3] = rep
else:
  lo = (via.getBottomLayer().getName(), via.getTopLayer().getName()); k = -1   # hop up or down
  for i in range(len(ops) - 2):
      a, b, c = ops[i], ops[i + 1], ops[i + 2]
      if a[0] == "PATH" and a[1].getName() in lo and b[0] == "PT" and c[0] == "PT" and b[1] == hx and c[1] == hx \
              and min(b[2], c[2]) <= y0 < max(b[2], c[2]):   # y1 may lie beyond the segment end (the wire steps back to it)
          k = i; break
  if k < 0:
      for i, o in enumerate(ops):
          if o[0] in ("PT", "PTX") and o[1] == hx: print("R28_HOP near", i, [str(x) if not isinstance(x, (int, str)) else x for x in ops[max(0, i - 2):i + 3]])
      sys.exit("R28_HOP segment not found")
  ya, yb = ops[k + 1][2], ops[k + 2][2]
  p, q = (y0, y1) if ya <= yb else (y1, y0)
  ops[k:k + 3] = [ops[k], ops[k + 1], ["PT", hx, p], ["TVIA", via], ["PT", hx, q], ["TVIA", via], ops[k + 2]]
n_ops = len(ops)
# write the new op list; impl/r28/eco28.tcl (QB28_HOP_OPS) re-encodes the wire (odb in Python has no logger for errors)
with open(os.environ["QB28_OUT"], "w") as f:
    for o in ops:
        t = o[0]
        if t == "PATH": f.write("PATH %s %s\n" % (o[1].getName(), o[2]))
        elif t in ("PT", "PTX", "RECT"): f.write("%s %s\n" % (t, " ".join(str(v) for v in o[1:])))
        elif t in ("VIA", "TVIA"): f.write("%s %s\n" % (t, o[1].getName()))
        elif t == "ITERM": f.write("ITERM %s %s\n" % (o[1].getInst().getName(), o[1].getMTerm().getName()))
        elif t == "BTERM": f.write("BTERM %s\n" % o[1].getName())
print("R28_HOP %s segment %d..%d at x %d hopped %d-%d via %s, %d ops -> %s" % (net_n, ya, yb, hx, y0, y1, vname, n_ops, os.environ["QB28_OUT"]))
