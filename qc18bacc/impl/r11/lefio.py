"""R11: minimal LEF macro reader / writer for the block proxies (impl/r11/act_lef.py, fp11.py)."""
import re


def read_macro(path):
    """-> (name, W, H, {pin: (dir, layer, x1, y1, x2, y2)}) of the first MACRO in <path> (first rect per pin)."""
    t = open(path).read()
    m = re.search(r"\nMACRO (\S+)(.*?)\nEND \1", t, re.S)
    name, body = m.group(1), m.group(2)
    W, H = map(float, re.search(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", body).groups())
    pins = {}
    for pm in re.finditer(r"\n\s*PIN (\S+)(.*?)\n\s*END \1", body, re.S):
        d = re.search(r"DIRECTION (\w+)", pm.group(2))
        r = re.search(r"LAYER (\S+) ;\s*RECT\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)", pm.group(2))
        if r:
            pins[pm.group(1)] = ((d.group(1) if d else "INPUT"), r.group(1)) + tuple(map(float, r.groups()[1:]))
    return name, W, H, pins


def write_macro(path, name, W, H, pins, obs_layers, inset=0.9, extra_obs=None):
    """pins: {name: (dir, layer, x1, y1, x2, y2)}; full-area OBS on obs_layers, inset from the die edge."""
    with open(path, "w") as f:
        f.write("VERSION 5.8 ;\nBUSBITCHARS \"[]\" ;\nDIVIDERCHAR \"/\" ;\n\nMACRO %s\n  CLASS BLOCK ;\n  ORIGIN 0 0 ;\n"
                "  FOREIGN %s 0 0 ;\n  SIZE %.3f BY %.3f ;\n  SYMMETRY X Y ;\n" % (name, name, W, H))
        for p, (d, ly, x1, y1, x2, y2) in sorted(pins.items()):
            use = "CLOCK" if p == "clk" else "SIGNAL"
            f.write("  PIN %s\n    DIRECTION %s ;\n    USE %s ;\n    PORT\n      LAYER %s ;\n        RECT %.3f %.3f %.3f %.3f ;\n"
                    "    END\n  END %s\n" % (p, d, use, ly, x1, y1, x2, y2, p))
        f.write("  OBS\n")
        for ly in obs_layers:
            f.write("    LAYER %s ;\n      RECT %.3f %.3f %.3f %.3f ;\n" % (ly, inset, inset, W - inset, H - inset))
        for ly, r in (extra_obs or []):
            f.write("    LAYER %s ;\n      RECT %.3f %.3f %.3f %.3f ;\n" % ((ly,) + r))
        f.write("  END\nEND %s\n\nEND LIBRARY\n" % name)
