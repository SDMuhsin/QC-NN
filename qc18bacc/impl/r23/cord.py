"""R23 (results/r23.md): physical column order (opt-in env QB_CORD, e.g. 04152637 = logical column order[i] in physical
slot i; unset / 01234567 = identity, the default everywhere).  A column's index matters only through its connectivity
(hub column pins, S lanes 8 r + c, params c, qb_col_blk g_c_<c>), so the order is a purely physical choice."""
import os
def order():
    o = os.environ.get("QB_CORD", "01234567")
    assert sorted(o) == list("01234567"), "QB_CORD %s is not a permutation of 0..7" % o
    return [int(ch) for ch in o]
def pos():
    """logical column -> physical slot"""
    return {c: s for s, c in enumerate(order())}
def identity():
    return order() == list(range(8))
