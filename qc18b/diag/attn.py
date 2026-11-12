"""Attention-map agreement of block outputs (measurement only).

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.diag.attn --bin BIN.pt --scratch SCR.pt --fp FP.pt --out qc18b/diag/results/attn

Models (eval, fp32, TF32 off) built as qc18b.diag.diagnose (binact options from the train.log line 'binact=', missing
stem_therm / fp_blocks keys default to 0 / ''); FP = preact, act=False.  Data: val[:2000] of the 45k/5k split.
s_k = block k output (pre-ReLU, block forward output).  Attention map exactly as larq_zoo AttentionMatchingLossLayer
(_normalized_attention_vector): A = mean over channels of a^2 (H x W), flattened, divided by its per-image max;
R2B loss (_layer_attention_loss) = mean over positions of (q_s - q_t)^2 per image (reported: mean over images;
larq_zoo then averages over layers and multiplies by loss_weight).  cos = cosine of the two flattened maps per image
(scale invariant, so identical for max- or L2-normalisation), mean over images.
Pairs: BIN vs FP, SCR vs FP, FPflip vs FP (FP on horizontally flipped inputs, maps flipped back).
b1 rows: per-position L2 norm sqrt(sum_c b^2) of the 1-bit tensor b1 of block k+1 (input s_k) vs FP map of relu(s_k):
cos_l2 = vs FP per-position L2 norm of relu(s_k); cos_att = vs FP attention map of relu(s_k).
"""
import argparse
import json
import os

import torch
import torch.nn.functional as F

from qc18b import data
from qc18b.diag.diagnose import build_fp

torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False
N = 2000
BS = 500


def build_bin(ckpt, dev):
    with open(os.path.join(os.path.dirname(ckpt), "train.log")) as f:
        line = next(ln for ln in f if ln.startswith("binact=")).split()
    o = dict(kv.split("=", 1) for kv in line)
    assert o["arch"] == "qc18" and o.get("stem_therm", "0") == "0" and o.get("fp_blocks", "") == "" \
        and o["preact"] == "1", o
    m, _ = build_fp(ckpt, dev, dict(ste=o["ste"], w=float(o["w"]), act=bool(int(o["binact"])), k=float(o["K"]),
                                    t_train=int(o["t_train"]), preact=1))
    return m.eval(), o


def att(a):
    """[N, C, H, W] -> larq_zoo normalised attention vector [N, H*W]."""
    v = a.double().pow(2).mean(1).flatten(1)
    return v / v.max(1, keepdim=True).values


def l2map(a):
    return a.double().pow(2).sum(1).sqrt().flatten(1)


@torch.no_grad()
def collect(m, x, flip=False):
    """-> {'s': [8 x [N,C,H,W]] block outputs, 'b1': [8 x ...] b1 outputs} (flipped back if flip)."""
    S = {"s": [[] for _ in m.blocks], "b1": [[] for _ in m.blocks]}
    hs = []
    for k, blk in enumerate(m.blocks):
        hs.append(blk.register_forward_hook(lambda mm, i, o, k=k: S["s"][k].append(o.float())))
        hs.append(blk.b1.register_forward_hook(lambda mm, i, o, k=k: S["b1"][k].append(o.float())))
    try:
        for i in range(0, len(x), BS):
            xb = x[i:i + BS]
            m(data.prep(xb.flip(2) if flip else xb))
    finally:
        for h in hs:
            h.remove()
    out = {}
    for key, L in S.items():
        out[key] = [torch.cat(t).contiguous() for t in L]
        if flip:
            out[key] = [t.flip(-1) for t in out[key]]
    return out


def cos(p, q):
    return F.cosine_similarity(p, q, dim=1).mean().item()


def r2b(p, q):
    return (p - q).pow(2).mean(1).mean().item()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--scratch", required=True)
    ap.add_argument("--fp", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    dev = "cuda"
    _, (xva, _) = data.split(dev)
    x = xva[:N]
    fp, _ = build_fp(a.fp, dev)
    fp.eval()
    F0 = collect(fp, x)
    Ff = collect(fp, x, flip=True)
    feats = {"FP": F0, "FPflip": Ff}
    opts = {}
    for tag, p in (("BIN", a.bin), ("SCR", a.scratch)):
        m, opts[tag] = build_bin(p, dev)
        feats[tag] = collect(m, x)
        for k, b in enumerate(feats[tag]["b1"]):
            assert bool(((b == 0) | (b == 1)).all()), (tag, k)
        del m
        torch.cuda.empty_cache()
    rows = []
    for k in range(len(fp.blocks)):
        r = dict(block=k)
        for kind, f in (("s", lambda t: t), ("relu", F.relu)):
            qt = att(f(F0["s"][k]))
            for tag in ("BIN", "SCR", "FPflip"):
                qs = att(f(feats[tag]["s"][k]))
                r[f"{kind}/{tag}/cos"] = cos(qs, qt)
                r[f"{kind}/{tag}/r2b"] = r2b(qs, qt)
        if k + 1 < len(fp.blocks):
            rt = F.relu(F0["s"][k])
            lt, at = l2map(rt), att(rt)
            for tag in ("BIN", "SCR"):
                lb = l2map(feats[tag]["b1"][k + 1])
                r[f"b1/{tag}/cos_l2"] = cos(lb, lt)
                r[f"b1/{tag}/cos_att"] = cos(lb, at)
            lf = l2map(F.relu(Ff["s"][k]))
            r["b1/FPflip/cos_l2"] = cos(lf, lt)
        r["HW"] = list(F0["s"][k].shape[2:])
        rows.append(r)
        print(k, {kk: round(v, 4) for kk, v in r.items() if isinstance(v, float)}, flush=True)
    json.dump(dict(bin=a.bin, scratch=a.scratch, fp=a.fp, opts=opts, n=N, rows=rows), open(a.out + ".json", "w"), indent=1)
    f3 = lambda v: f"{v:.3f}"
    f4 = lambda v: f"{v:.4f}"
    L = ["# Attention-map agreement with FP (measured)", "",
         f"BIN `{a.bin}`, BIN-scratch (SCR) `{a.scratch}`, FP `{a.fp}`; val[:{N}], eval, fp32. "
         "FPflip = FP on horizontally flipped inputs, maps flipped back (reference).", "",
         "larq_zoo `AttentionMatchingLossLayer` (Real-to-Binary sec. 4.2): tensor = block output (Lambda `{name}_out`, "
         "after the skip add, before the next block's BN/sign; here s_k pre-ReLU); "
         "map = `reduce_mean(square(a), axis=-1)` (mean over channels), flattened, divided by per-image max "
         "(not L2); loss = `reduce_mean(square(qs - qt), axis=-1)` per image (then mean over layers x loss_weight). "
         "cos = per-image cosine of the flattened maps (scale invariant), mean over images; r2b = mean over images of the "
         "per-image loss.", ""]
    for kind, title in (("s", "s_k (pre-ReLU)"), ("relu", "relu(s_k)")):
        L += [f"## {title}", "", "| block | HxW | cos BIN-FP | cos SCR-FP | cos FPflip-FP | r2b BIN-FP | r2b SCR-FP | r2b FPflip-FP |",
              "|---|---|---|---|---|---|---|---|"]
        for r in rows:
            L.append(f"| {r['block']} | {r['HW'][0]}x{r['HW'][1]} | " + " | ".join(
                [f3(r[f"{kind}/{t}/cos"]) for t in ("BIN", "SCR", "FPflip")] +
                [f4(r[f"{kind}/{t}/r2b"]) for t in ("BIN", "SCR", "FPflip")]) + " |")
        L.append("")
    L += ["## b1 of block k+1 (1-bit, input s_k): per-position L2 norm map vs FP relu(s_k)", "",
          "cos_l2: vs FP per-position L2 norm of relu(s_k); cos_att: vs FP attention map of relu(s_k); "
          "FPflip row: FP relu(s_k) L2 map on flipped inputs vs FP.", "",
          "| k | cos_l2 BIN | cos_l2 SCR | cos_att BIN | cos_att SCR | cos_l2 FPflip |", "|---|---|---|---|---|---|"]
    for r in rows:
        if "b1/BIN/cos_l2" in r:
            L.append(f"| {r['block']} | " + " | ".join(f3(r[c]) for c in (
                "b1/BIN/cos_l2", "b1/SCR/cos_l2", "b1/BIN/cos_att", "b1/SCR/cos_att", "b1/FPflip/cos_l2")) + " |")
    open(a.out + ".md", "w").write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
