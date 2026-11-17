"""R18: net class of a nets.txt line (impl/r18/dump.tcl): root driver walked back through buffers + leaf sink categories."""
import re, collections as C
def klass(rc, rn, nl, lv):
    if rc == "clock": return "clock"
    L = C.Counter()
    if lv != "-":
        for t in lv.split(","):
            k, v = t.rsplit(":", 1); L[k] += int(v)
    if rc == "pm": return "lbm S1-term-in"
    if rc == "lbff":
        p, l = L["pm"], L["lbff"] + L["lbc"]
        return "lbf pre-mux-in" if p and not l else "lb slot-shift" if l and not p else "lbf+shift" if p and l else "lb other"
    if rc == "wdq": return "lb write rdq/sdq"
    if rc.startswith("sel:"): return "sel " + rc[4:]
    if rc == "s1c": return "S1 int->reg" if L["s1ff"] else "S1 int tree"
    if rc in ("s1ff", "s2c", "s2ff"): return "S2 nets"
    if nl >= 64: return "sel other-bcast"
    if rc == "lbc": return "lb D-local" if nl <= 1 else "lb D-fan(wd)"
    if rc == "port" and re.match(r"(s_q|m_q)", rn): return "lb wsrc s_q/m_q"
    if rc in ("apipe", "dist", "port"): return "act pipe/ports"
    return "other"
def load(fn):
    NC = {}
    for ln in open(fn):
        t = ln.split()
        if len(t) >= 5: NC[t[0]] = klass(t[1], t[2], int(t[3]), t[4])
    return NC
