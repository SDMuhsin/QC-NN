"""IntNet (qc18/int8.py) built exactly as qc18.int8.main does, and its per-pass integer maps."""
import torch
import torch.nn.functional as F

from qc18.data import prep, split
from qc18.int8 import IntNet, float_acts, igemm, requant
from qc18.verify import load


@torch.no_grad()
def build_intnet(ckpt, dev, calib=2000):
    """Same calibration as qc18.int8.main (max|a|/127 per tensor on train[:calib], batches of 500)."""
    ck, model = load(ckpt, dev)
    args = ck["args"]
    assert args["mode"] == "signed" and args["b"] == 8 and args.get("relax", "none") == "none"
    (xt, _), _ = split(dev)
    xc = prep(xt[:calib])
    mx = None
    for i in range(0, len(xc), 500):
        m = [t.abs().amax().double() for t in float_acts(model, xc[i:i + 500])]
        mx = m if mx is None else [torch.maximum(u, v) for u, v in zip(mx, m)]
    S = [v.item() / 127 for v in mx]
    return IntNet(model, S, True), model


@torch.no_grad()
def maps(net, x):
    """x: prep()'d float64 batch -> (q_in, {pass name: int map}, pooled p, int32 FC accumulators + bias).
    Mirrors IntNet.__call__ step by step and checks it reproduces IntNet's own logits."""
    q = torch.round(x.double() / net.S0).clamp(-127, 127).long()
    q_in, out = q, {}
    q = out["stem"] = requant(net.stem.acc(q), *net.stem_m, 0, 127)
    for i, e in enumerate(net.blocks):
        n = f"blocks.{i}"
        t = out[n + ".c1"] = requant(e["c1"].acc(q), *e["c1m"], 0, 127)
        if "sc" in e:
            sc = out[n + ".sc"] = requant(e["sc"].acc(q), *e["scm"])
        else:
            sc = requant(q, *e["idm"])
        q = out[n + ".c2"] = (requant(e["c2"].acc(t), *e["c2m"]) + sc).clamp(0, 127)
    p = requant(q.sum(dim=(2, 3)), *net.pool_m, 0, 127)
    acc = igemm(F.linear, p, net.fW8) + net.fbq
    assert torch.equal(acc.double() * net.fscale, net(x)), "mirror != IntNet"
    return q_in, out, p, acc
