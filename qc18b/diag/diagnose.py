"""BIN vs FP-activation comparison of two preact qc18-arch models (measurement only).

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.diag.diagnose --bin BIN.pt --fp FP.pt --out qc18b/diag/results/diagnose

BIN: rebuilt with qc18b.diag.fidelity.build (checkpoint args + line 1 of its train.log).  FP: same args, binarize(act=False,
preact=1) (ReLU in place of BinAct, same function as qc18).  Eval mode, fp32, TF32 off.  train = first 10k of the 45k
train split (no aug), val = 5k val split.  s_k = block k output (pre-ReLU), s_stem = stem BN output.
D1 (a) probe: GAP(relu(s)) -> standardise (train mean/std) -> multinomial logistic regression (L2 wd, Adam full batch,
    STEPS steps); (lr, wd) chosen on held-out train[8000:10000] after fitting on train[:8000], refit on all 10k.
    (b) linear CKA BIN vs FP: pooled = GAP(relu(s)) on 5k val; unpooled = relu(s) flattened (C*H*W) on val[:2000].
D2 BinAct input x (BIN; FP: input of the ReLU in the same slot), u = x - t_c (FP: t = 0), z = u / std_c(x) over val:
    fractions |z| < .1/.25/.5; per-channel p1 = mean 1[u > 0]: min / p10 / median / p90 / max over channels.
D3 per QCConv2d pre-BN output on val; BIN block convs (binary input): distinct values, min, max, std, frac == 0,
    nnz weights per output channel (mean), active terms per output element = conv(b, |w|) (mean); FP: std.
D4 per block on val: branch = c2 BN output, identity = relu(s_in) (sc BN output in downsampling blocks);
    ratio = ||branch|| / ||identity||, cosine = <branch, identity> / (||.|| ||.||), sums over all elements.
D5 CE / acc on train10k and val; per-class train-acc gap FP - BIN.
D6 per BN: median |gamma|, median |beta|, median sqrt(running_var).
"""
import argparse
import copy
import json
import os
import time

import torch
import torch.nn as nn
import torch.nn.functional as F

from qc18.model import QCResNet18
from qc18.qcconv import QCConv2d
from qc18b import binact, data

torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False
BS = 500
STEPS = 500
GRID = [(lr, wd) for lr in (1e-3, 1e-2, 1e-1) for wd in (1e-4, 1e-3, 1e-2, 1e-1)]
NCKA = 2000


def build_bin(ckpt, dev):
    """as qc18b.diag.fidelity.build, but the binact options are read from the train.log line starting 'binact='
    (line 1 is the --init message in runs started with --init)."""
    with open(os.path.join(os.path.dirname(ckpt), "train.log")) as f:
        line = next(ln for ln in f if ln.startswith("binact=")).split()
    o = dict(kv.split("=", 1) for kv in line)
    assert o["arch"] == "qc18" and o["stem_therm"] == "0" and o["fp_blocks"] == "" and o["preact"] == "1", o
    m, ck = build_fp(ckpt, dev, dict(ste=o["ste"], w=float(o["w"]), act=bool(int(o["binact"])), k=float(o["K"]),
                                     t_train=int(o["t_train"]), preact=1))
    return m, ck, o


def build_fp(ckpt, dev, bo=None):
    ck = torch.load(ckpt, map_location=dev, weights_only=False)
    a = ck["args"]
    m = QCResNet18(a["mode"], a["b"], a["estimator"], a["tau0"], num_classes=data.NUM_CLASSES, relax=a["relax"],
                   qinit_scale=a["qinit_scale"], homotopy=a["homotopy"]).to(dev).to(memory_format=torch.channels_last)
    bo = bo or dict(ste="clip", w=1.0, act=False, k=1.0, t_train=1, preact=1)
    m = binact.binarize(m, bo["ste"], bo["w"], 0, "", 0, 1, False, act=bo["act"], k=bo["k"], t_train=bo["t_train"],
                        preact=bo["preact"])
    m.load_state_dict(ck["state"])
    if a["homotopy"] != "none":
        m.set_homotopy(False)
    return m, ck


def feat_names(m):
    return ["stem"] + [f"block{k}" for k in range(len(m.blocks))]


def feat_mods(m):
    return [m.stem] + list(m.blocks)


@torch.no_grad()
def run(m, x, y, hooks_fn=None, pooled=True):
    """-> logits [N, 100] and pooled relu(s) per feature layer (list of [N, C])."""
    pools = [[] for _ in feat_mods(m)]
    hs = [mod.register_forward_hook(lambda mm, i, o, j=j: pools[j].append(F.relu(o).mean((2, 3)).double()))
          for j, mod in enumerate(feat_mods(m))] if pooled else []
    if hooks_fn:
        hs += hooks_fn()
    logits = []
    try:
        for i in range(0, len(x), BS):
            logits.append(m(data.prep(x[i:i + BS])).double())
    finally:
        for h in hs:
            h.remove()
    return torch.cat(logits), [torch.cat(p) if p else None for p in pools]


def probe(Ftr, ytr, Fva, yva):
    mu, sd = Ftr.mean(0), Ftr.std(0).clamp_min(1e-8)
    Xtr, Xva = ((Ftr - mu) / sd).float(), ((Fva - mu) / sd).float()

    def fit(X, y, lr, wd):
        torch.manual_seed(0)
        W = torch.zeros(X.shape[1], data.NUM_CLASSES, device=X.device, requires_grad=True)
        b = torch.zeros(data.NUM_CLASSES, device=X.device, requires_grad=True)
        opt = torch.optim.Adam([W, b], lr=lr)
        for _ in range(STEPS):
            opt.zero_grad()
            (F.cross_entropy(X @ W + b, y) + 0.5 * wd * (W * W).sum()).backward()
            opt.step()
        return lambda Z: (Z @ W + b).detach()

    acc = lambda f, X, y: (f(X).argmax(1) == y).float().mean().item()
    sel = []
    for lr, wd in GRID:
        f = fit(Xtr[:8000], ytr[:8000], lr, wd)
        sel.append(dict(lr=lr, wd=wd, held=acc(f, Xtr[8000:], ytr[8000:])))
    best = max(sel, key=lambda r: r["held"])
    f = fit(Xtr, ytr, best["lr"], best["wd"])
    return dict(train=acc(f, Xtr, ytr), val=acc(f, Xva, yva), lr=best["lr"], wd=best["wd"], held=best["held"], grid=sel)


def cka_feat(X, Y):
    X, Y = X - X.mean(0), Y - Y.mean(0)
    return ((Y.T @ X).norm() ** 2 / ((X.T @ X).norm() * (Y.T @ Y).norm())).item()


def cka_gram(K, L):
    n = K.shape[0]
    H = torch.eye(n, dtype=K.dtype, device=K.device) - 1.0 / n
    Kc, Lc = H @ K @ H, H @ L @ H
    return ((Kc * Lc).sum() / ((Kc * Kc).sum() * (Lc * Lc).sum()).sqrt()).item()


@torch.no_grad()
def grams(m, x):
    G = [torch.zeros(len(x), len(x), dtype=torch.float64, device=x.device) for _ in feat_mods(m)]
    feats = [[] for _ in feat_mods(m)]
    hs = [mod.register_forward_hook(lambda mm, i, o, j=j: feats[j].append(F.relu(o).flatten(1).contiguous()))
          for j, mod in enumerate(feat_mods(m))]
    try:
        for i in range(0, len(x), BS):
            m(data.prep(x[i:i + BS]))
    finally:
        for h in hs:
            h.remove()
    for j in range(len(G)):
        X = torch.cat(feats[j])
        feats[j] = None
        for c in range(0, X.shape[1], 8192):
            Xc = X[:, c:c + 8192].double()
            G[j] += Xc @ Xc.T
        del X
        torch.cuda.empty_cache()
    return G


def act_slots(m):
    """[(name, module)] of the activation slots b1 / b2 of every block (BinAct in BIN, ReLU in FP)."""
    return [(f"blocks.{k}.{s}", getattr(blk, s)) for k, blk in enumerate(m.blocks) for s in ("b1", "b2")]


@torch.no_grad()
def d2(m, x):
    slots = act_slots(m)
    thr = {n: (mod.t.detach().double() if isinstance(mod, binact.BinAct) else None) for n, mod in slots}
    acc = {}

    def u_of(n, inp):
        u = inp[0].double()
        t = thr[n]
        return u if t is None else u - t.view(1, -1, 1, 1)

    def p1(mod, inp, n):
        u = u_of(n, inp)
        a = acc.setdefault(n, dict(n=0, s=0, ss=0, pos=0))
        a["n"] += u.shape[0] * u.shape[2] * u.shape[3]
        a["s"] = a["s"] + u.sum((0, 2, 3))
        a["ss"] = a["ss"] + (u * u).sum((0, 2, 3))
        a["pos"] = a["pos"] + (u > 0).double().sum((0, 2, 3))

    run(m, x, None, lambda: [mod.register_forward_pre_hook(lambda mm, i, n=n: p1(mm, i, n)) for n, mod in slots], pooled=False)
    for a in acc.values():
        a["std"] = (a["ss"] / a["n"] - (a["s"] / a["n"]) ** 2).clamp_min(0).sqrt()   # std of x per channel
        a["lt"] = torch.zeros(3, dtype=torch.float64, device=x.device)

    def p2(mod, inp, n):
        a = acc[n]
        z = (u_of(n, inp) / a["std"].clamp_min(1e-30).view(1, -1, 1, 1)).abs()
        for i, c in enumerate((0.1, 0.25, 0.5)):
            a["lt"][i] += (z < c).double().sum()

    run(m, x, None, lambda: [mod.register_forward_pre_hook(lambda mm, i, n=n: p2(mm, i, n)) for n, mod in slots], pooled=False)
    out = []
    for n, _ in slots:
        a = acc[n]
        C = a["s"].numel()
        p = (a["pos"] / a["n"]).float()
        q = torch.quantile(p, torch.tensor([0, 0.1, 0.5, 0.9, 1.0], device=p.device)).tolist()
        fr = (a["lt"] / (a["n"] * C)).tolist()
        out.append(dict(layer=n, C=C, lt01=fr[0], lt025=fr[1], lt05=fr[2], p1_min=q[0], p1_p10=q[1], p1_med=q[2],
                        p1_p90=q[3], p1_max=q[4], zero_std_ch=int((a["std"] == 0).sum())))
    return out


@torch.no_grad()
def d3(m, x, binary):
    convs = [(n, c) for n, c in m.named_modules() if isinstance(c, QCConv2d)]
    acc = {}

    def hk(mod, inp, out, n):
        a = acc.setdefault(n, dict(n=0, s=0.0, ss=0.0, zero=0, mn=float("inf"), mx=float("-inf"), vals=set(), act=0.0,
                                   nonint=0, inbin=True))
        o = out.double()
        if binary and n != "stem.conv":
            xi = inp[0]
            a["inbin"] &= bool(((xi == 0) | (xi == 1)).all())
            ex = F.conv2d(xi.double(), mod.get_weight().double(), stride=mod.stride, padding=mod.padding)  # exact integers
            a["fp32err"] = max(a.get("fp32err", 0.0), (o - ex).abs().max().item())   # module (cuDNN fp32) vs exact
            o = ex
            a["nonint"] += int((o != o.round()).sum())
            a["zero"] += int((o == 0).sum())
            a["mn"], a["mx"] = min(a["mn"], o.min().item()), max(a["mx"], o.max().item())
            a["vals"] |= set(torch.unique(o).long().tolist())
            w = mod.get_weight().abs()
            a["act"] += F.conv2d(xi.double(), w.double(), stride=mod.stride, padding=mod.padding).sum().item()
        a["n"] += o.numel()
        a["s"] += o.sum().item()
        a["ss"] += (o * o).sum().item()

    run(m, x, None, lambda: [c.register_forward_hook(lambda mm, i, o, n=n: hk(mm, i, o, n)) for n, c in convs], pooled=False)
    out = []
    for n, c in convs:
        a = acc[n]
        mu = a["s"] / a["n"]
        r = dict(layer=n, std=(a["ss"] / a["n"] - mu * mu) ** 0.5, mean=mu)
        if binary and n != "stem.conv":
            w = c.get_weight()
            assert bool(((w == 0) | (w == 1) | (w == -1)).all()), n
            r.update(distinct=len(a["vals"]), min=a["mn"], max=a["mx"], zero=a["zero"] / a["n"],
                     nnz_w=(w != 0).flatten(1).sum(1).double().mean().item(), fanin=w[0].numel(),
                     active=a["act"] / a["n"], nonint=a["nonint"], input_binary=a["inbin"], fp32err=a["fp32err"])
        out.append(r)
    return out


@torch.no_grad()
def d4(m, x):
    acc = {k: dict(bb=0.0, ii=0.0, bi=0.0) for k in range(len(m.blocks))}
    cur = {}
    hs = []
    for k, blk in enumerate(m.blocks):
        hs.append(blk.register_forward_pre_hook(lambda mm, i, k=k: cur.__setitem__(("in", k), i[0])))
        hs.append(blk.c2.register_forward_hook(lambda mm, i, o, k=k: cur.__setitem__(("br", k), o)))
        if blk.sc is not None:
            hs.append(blk.sc.register_forward_hook(lambda mm, i, o, k=k: cur.__setitem__(("id", k), o)))

        def post(mm, i, o, k=k):
            br = cur.pop(("br", k)).double()
            idt = cur.pop(("id", k)).double() if mm.sc is not None else F.relu(cur[("in", k)]).double()
            cur.pop(("in", k))
            assert torch.allclose((br + idt).float(), o, atol=1e-4, rtol=1e-4), k     # out = branch + identity
            a = acc[k]
            a["bb"] += (br * br).sum().item()
            a["ii"] += (idt * idt).sum().item()
            a["bi"] += (br * idt).sum().item()
        hs.append(blk.register_forward_hook(post))
    run(m, x, None, lambda: hs, pooled=False)
    return [dict(block=k, ratio=(a["bb"] / a["ii"]) ** 0.5, cos=a["bi"] / (a["bb"] * a["ii"]) ** 0.5,
                 ds=m.blocks[k].sc is not None) for k, a in acc.items()]


def d6(m):
    out = []
    for n, bn in m.named_modules():
        if isinstance(bn, nn.BatchNorm2d):
            out.append(dict(layer=n, gamma=bn.weight.abs().median().item(), beta=bn.bias.abs().median().item(),
                            rstd=bn.running_var.sqrt().median().item()))
    return out


DS = (2, 4, 6)
NDS = (0, 1, 3, 5, 7)


class Acc:
    """per-channel running sums for a pair (A, B) of [N, C, H, W] tensors (fp64)."""

    def __init__(self):
        self.n = 0
        self.s = None

    def add(self, A, B):
        t = dict(a=A.sum((0, 2, 3)), b=B.sum((0, 2, 3)), aa=(A * A).sum((0, 2, 3)), bb=(B * B).sum((0, 2, 3)),
                 ab=(A * B).sum((0, 2, 3)))
        self.s = t if self.s is None else {k: self.s[k] + v for k, v in t.items()}
        self.n += A.shape[0] * A.shape[2] * A.shape[3]

    def centred(self):
        """per-channel centred (aa, bb, ab) and channel means (ma, mb)."""
        s, n = self.s, self.n
        ma, mb = s["a"] / n, s["b"] / n
        return s["aa"] - n * ma * ma, s["bb"] - n * mb * mb, s["ab"] - n * ma * mb, ma, mb


def _bn(bn, z, stats=None):
    if stats is None:
        mu, var = bn.running_mean, bn.running_var
    else:
        mu, var = stats
    return (z - mu.view(1, -1, 1, 1)) / (var.view(1, -1, 1, 1) + bn.eps).sqrt() * bn.weight.view(1, -1, 1, 1) \
        + bn.bias.view(1, -1, 1, 1)


@torch.no_grad()
def collect789(md, x, binary, scstats=None, want_stats=False):
    """fp64 model md (eval).  -> pooled features {key: [N, C]} and accumulators.  scstats: {k: (mean, var)} of
    sc.conv(relu(s_{k-1})) (BIN) for the recomputed-BN variant; want_stats: return those stats instead."""
    feats, accs, cur, hs = {}, {}, {}, []
    put = lambda key, t: feats.setdefault(key, []).append(F.relu(t).mean((2, 3)))
    st = {}
    hs.append(md.stem.register_forward_hook(lambda mm, i, o: put(("s", -1), o)))
    for k, blk in enumerate(md.blocks):
        hs.append(blk.register_forward_pre_hook(lambda mm, i, k=k: cur.__setitem__("in", i[0])))
        hs.append(blk.b1.register_forward_hook(lambda mm, i, o, k=k: cur.__setitem__("h", o)))
        hs.append(blk.c2.register_forward_hook(lambda mm, i, o: cur.__setitem__("br", o)))
        if blk.sc is not None:
            hs.append(blk.sc.register_forward_hook(lambda mm, i, o: cur.__setitem__("sc", o)))

        def post(mm, i, o, k=k):
            s, h, br = cur.pop("in"), cur.pop("h"), cur.pop("br")
            if binary:
                assert bool(((h == 0) | (h == 1)).all()), k
                put(("b1", k), h)                                     # mean of the binary map (relu is identity)
            put(("s", k), o)
            if want_stats:
                if mm.sc is not None:
                    z = mm.sc.conv(F.relu(s))
                    a = st.setdefault(k, [0, 0.0, 0.0])
                    a[0] += z.shape[0] * z.shape[2] * z.shape[3]
                    a[1] = a[1] + z.sum((0, 2, 3))
                    a[2] = a[2] + (z * z).sum((0, 2, 3))
                cur.pop("sc", None)
                return
            if mm.sc is not None:
                sc = cur.pop("sc")
                assert torch.allclose(br + sc, o, atol=1e-9, rtol=1e-9), k
                put(("in", k), s)
                put(("sc", k), sc)
                put(("br", k), br)
                if binary:
                    z = mm.sc.conv(F.relu(s))
                    v = mm.sc.bn(z)                                   # eval BN, stored running stats
                    put(("v", k), v)
                    if scstats is not None:
                        put(("vr", k), _bn(mm.sc.bn, z, scstats[k]))
                    accs.setdefault(("v", k), Acc()).add(sc, v)
            else:
                idt = F.relu(s)
                assert torch.allclose(br + idt, o, atol=1e-9, rtol=1e-9), k
                accs.setdefault(("d8", k), Acc()).add(br, idt)
        hs.append(blk.register_forward_hook(post))
    try:
        for i in range(0, len(x), BS):
            md(data.prep(x[i:i + BS], torch.float64))
    finally:
        for h in hs:
            h.remove()
    if want_stats:
        return {k: (a[1] / a[0], a[2] / a[0] - (a[1] / a[0]) ** 2) for k, a in st.items()}
    return {key: torch.cat(v) for key, v in feats.items()}, accs


def main789(a, dev, log):
    (xtr, ytr), (xva, yva) = data.split(dev)
    xtr, ytr = xtr[:10000], ytr[:10000]
    mb, _, ob = build_bin(a.bin, dev)
    mf, _ = build_fp(a.fp, dev)
    R = dict(bin=a.bin, fp=a.fp, bin_opts=ob, d7={}, d7err={}, d8={}, d9=[])
    F_, A_ = {}, {}
    for tag, m, binary in (("BIN", mb, True), ("FP", mf, False)):
        md = copy.deepcopy(m).double().eval()
        del m
        ss = collect789(md, xtr, binary, want_stats=True) if binary else None
        ft, _ = collect789(md, xtr, binary, ss)
        fv, av = collect789(md, xva, binary, ss)
        with torch.no_grad():
            R.setdefault("val_fp64", {})[tag] = sum((md(data.prep(xva[i:i + BS], torch.float64)).argmax(1) == yva[i:i + BS])
                                                   .sum().item() for i in range(0, len(xva), BS)) / len(xva)
        F_[tag], A_[tag] = (ft, fv), av
        del md
        torch.cuda.empty_cache()
        log(f"{tag} collected, fp64 val {R['val_fp64'][tag]:.4f}")
    pr = lambda tag, key: probe(F_[tag][0][key], ytr, F_[tag][1][key], yva)
    # D7
    for k in DS:
        for tag in ("BIN", "FP"):
            keys = [("i", ("s", k - 1)), ("ii", ("sc", k)), ("iii", ("br", k)), ("iv", ("s", k))]
            if tag == "BIN":
                keys += [("v", ("v", k)), ("v_bnrec", ("vr", k))]
            for nm, key in keys:
                p = pr(tag, key)
                R["d7"][f"{tag}/{k}/{nm}"] = {kk: p[kk] for kk in ("train", "val", "lr", "wd")}
            log(f"D7 {tag} block{k} " + " ".join(f"{nm} {100 * R['d7'][f'{tag}/{k}/{nm}']['val']:.2f}" for nm, _ in keys))
        aa, bb, ab, _, _ = A_["BIN"][("v", k)].centred()
        al = ab.sum() / bb.sum()
        err = ((aa.sum() - 2 * al * ab.sum() + al * al * bb.sum()) / aa.sum()).clamp_min(0).sqrt()
        alc = ab / bb.clamp_min(1e-300)                                     # per-channel alpha
        errc = ((aa - alc * ab).sum() / aa.sum()).clamp_min(0).sqrt()
        R["d7err"][k] = dict(alpha=al.item(), rel_err=err.item(), rel_err_perch_alpha=errc.item(),
                             cos_centred=(ab.sum() / (aa.sum() * bb.sum()).sqrt()).item())
        log(f"D7 err block{k} {R['d7err'][k]}")
    # D8
    for k in NDS:
        for tag in ("BIN", "FP"):
            A = A_[tag][("d8", k)]
            aa, bb, ab, ma, mb_ = A.centred()
            s = A.s
            R["d8"][f"{tag}/{k}"] = dict(cos_centred=(ab.sum() / (aa.sum() * bb.sum()).sqrt()).item(),
                                         cos_raw=(s["ab"].sum() / (s["aa"].sum() * s["bb"].sum()).sqrt()).item(),
                                         med_mean_branch=ma.median().item(), med_mean_id=mb_.median().item(),
                                         frac_opp=((ma * mb_) < 0).double().mean().item(),
                                         frac_id_zero=(mb_ == 0).double().mean().item())
    log("D8 done")
    # D9
    for k in range(-1, len(mb.blocks) - 1):
        r = dict(block=k, relu_s=pr("BIN", ("s", k)), b1_next=pr("BIN", ("b1", k + 1)))
        R["d9"].append({kk: (v if not isinstance(v, dict) else {q: v[q] for q in ("train", "val", "lr", "wd")})
                        for kk, v in r.items()})
        log(f"D9 {k} {100 * r['relu_s']['val']:.2f} vs {100 * r['b1_next']['val']:.2f}")
    with open(a.out + "_d789.json", "w") as fh:
        json.dump({**R, "d7err": {str(k): v for k, v in R["d7err"].items()}}, fh, indent=1)
    append_md789(R, a.out + ".md")


def append_md789(R, path):
    v = lambda d: f"{100 * d['val']:.2f}"
    t = lambda d: f"{100 * d['train']:.2f}"
    L = ["", "## D7 downsampling blocks: probe on pooled relu() of block input / shortcut / branch / output (acc %, train / val)", "",
         "All D7-D9 tensors from an fp64 copy of each model (BIN block convs integer-exact); fp64 val acc "
         f"BIN {100 * R['val_fp64']['BIN']:.2f}, FP {100 * R['val_fp64']['FP']:.2f}.  Probe protocol as D1.  "
         "(i) s_{k-1}; (ii) sc-BN output; (iii) c2-BN output; (iv) s_k; (v) BIN only: sc-BN(sc-conv(relu(s_{k-1}))) with "
         "stored eval BN; (v') same with BN mean/var recomputed on the 10k train set (sc-conv(relu(s)) statistics, biased var), "
         "stored gamma/beta.", "",
         "| block | model | (i) in | (ii) sc | (iii) branch | (iv) out | (v) sc(relu s), eval BN | (v') sc(relu s), BN recomputed |",
         "|---|---|---|---|---|---|---|---|"]
    for k in (2, 4, 6):
        for tag in ("BIN", "FP"):
            d = lambda nm: R["d7"].get(f"{tag}/{k}/{nm}")
            cells = [f"{t(d(nm))} / {v(d(nm))}" if d(nm) else "-" for nm in ("i", "ii", "iii", "iv", "v", "v_bnrec")]
            L.append(f"| {k} | {tag} | " + " | ".join(cells) + " |")
    L += ["", "BIN shortcut on binary vs FP input (val): A = sc(b1(s)), B = sc(relu(s)) (both sc-BN outputs, eval BN), each "
          "channel's mean over (N,H,W) removed; scalar alpha = <A,B>/<B,B>; rel err = ||A - alpha B|| / ||A||; also with a "
          "per-channel alpha, and centred cosine(A, B).", "",
          "| block | alpha | rel err (scalar alpha) | rel err (per-channel alpha) | centred cos |", "|---|---|---|---|---|"]
    for k, e in R["d7err"].items():
        L.append(f"| {k} | {e['alpha']:.4f} | {e['rel_err']:.4f} | {e['rel_err_perch_alpha']:.4f} | {e['cos_centred']:.4f} |")
    L += ["", "## D8 non-downsampling blocks: branch (c2-BN output) vs identity (relu(s_in)) (val)", "",
          "centred: each channel's mean over (N,H,W) removed from both; raw: as D4.  m_b, m_i = per-channel means of branch / "
          "identity; opp = fraction of channels with m_b * m_i < 0; m_i = 0 = fraction of channels with identity identically 0.", "",
          "| block | model | cos centred | cos raw | median m_b | median m_i | opp | m_i = 0 |", "|---|---|---|---|---|---|---|---|"]
    for k in (0, 1, 3, 5, 7):
        for tag in ("BIN", "FP"):
            d = R["d8"][f"{tag}/{k}"]
            L.append(f"| {k} | {tag} | {d['cos_centred']:.3f} | {d['cos_raw']:.3f} | {d['med_mean_branch']:.4f} | "
                     f"{d['med_mean_id']:.4f} | {d['frac_opp']:.3f} | {d['frac_id_zero']:.3f} |")
    L += ["", "## D9 BIN: probe on pooled relu(s_k) vs on pooled b1 of block k+1 (the binary map block k+1 consumes) (acc %)", "",
          "| k | relu(s_k) train | relu(s_k) val | b1_{k+1} train | b1_{k+1} val |", "|---|---|---|---|---|"]
    for r in R["d9"]:
        n = "stem" if r["block"] == -1 else r["block"]
        L.append(f"| {n} | {t(r['relu_s'])} | {v(r['relu_s'])} | {t(r['b1_next'])} | {v(r['b1_next'])} |")
    with open(path, "a") as fh:
        fh.write("\n".join(L) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--fp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--d789", action="store_true", help="only D7-D9; append to OUT.md, write OUT_d789.json")
    a = ap.parse_args()
    dev = "cuda"
    t0 = time.time()
    log = lambda s: print(f"[{time.time() - t0:7.1f}s] {s}", flush=True)
    if a.d789:
        return main789(a, dev, log)
    (xtr, ytr), (xva, yva) = data.split(dev)
    xtr, ytr = xtr[:10000], ytr[:10000]
    mb, ckb, ob = build_bin(a.bin, dev)
    mf, ckf = build_fp(a.fp, dev)
    M = {"BIN": mb, "FP": mf}
    saved = {"BIN": ckb["val"], "FP": ckf["val"]}
    for m in M.values():
        m.eval()
    R = dict(bin=a.bin, fp=a.fp, bin_opts=ob, names=feat_names(mb), models={})
    feats = {}
    for tag, m in M.items():
        lt, ft = run(m, xtr, ytr)
        lv, fv = run(m, xva, yva)
        feats[tag] = (ft, fv)
        pt, pv = lt.argmax(1), lv.argmax(1)
        cls = torch.stack([(pt[ytr == c] == c).double().mean() for c in range(data.NUM_CLASSES)])
        R["models"][tag] = dict(saved_val=saved[tag], val=(pv == yva).double().mean().item(), train=(pt == ytr).double().mean().item(),
                                ce_val=F.cross_entropy(lv, yva).item(), ce_train=F.cross_entropy(lt, ytr).item(), cls_train=cls.tolist())
        log(f"{tag} val {R['models'][tag]['val']:.4f} (saved {saved[tag]:.4f}) train {R['models'][tag]['train']:.4f}")
    for tag, m in M.items():                         # same weights, fp64 forward (exact integer convs in BIN)
        md = copy.deepcopy(m).double()
        with torch.no_grad():
            R["models"][tag]["val_fp64"] = sum((md(data.prep(xva[i:i + BS], torch.float64)).argmax(1) == yva[i:i + BS]).sum().item()
                                               for i in range(0, len(xva), BS)) / len(xva)
        del md
    gap = torch.tensor(R["models"]["FP"]["cls_train"]) - torch.tensor(R["models"]["BIN"]["cls_train"])
    fpc = torch.tensor(R["models"]["FP"]["cls_train"])
    top = gap.argsort(descending=True)[:5]
    R["d5"] = dict(gap_mean=gap.mean().item(), top5=[(int(c), gap[c].item(), fpc[c].item()) for c in top],
                   corr_gap_fp=torch.corrcoef(torch.stack([gap, fpc]))[0, 1].item())
    # D1
    R["d1"] = []
    G = {tag: grams(m, xva[:NCKA]) for tag, m in M.items()}
    for j, n in enumerate(R["names"]):
        r = dict(layer=n)
        for tag in M:
            ft, fv = feats[tag]
            r[tag] = probe(ft[j], ytr, fv[j], yva)
        r["cka_pooled"] = cka_feat(feats["BIN"][1][j], feats["FP"][1][j])
        r["cka_unpooled"] = cka_gram(G["BIN"][j], G["FP"][j])
        R["d1"].append(r)
        log(f"D1 {n} BIN {r['BIN']['train']:.3f}/{r['BIN']['val']:.3f} FP {r['FP']['train']:.3f}/{r['FP']['val']:.3f} "
            f"cka {r['cka_pooled']:.3f}/{r['cka_unpooled']:.3f}")
    del G
    torch.cuda.empty_cache()
    R["d2"] = {tag: d2(m, xva) for tag, m in M.items()}
    log("D2 done")
    R["d3"] = {"BIN": d3(mb, xva, True), "FP": d3(mf, xva, False)}
    log("D3 done")
    R["d4"] = {tag: d4(m, xva) for tag, m in M.items()}
    R["d6"] = {tag: d6(m) for tag, m in M.items()}
    with open(a.out + ".json", "w") as fh:
        json.dump(R, fh, indent=1)
    write_md(R, a.out + ".md")
    log("done")


def write_md(R, path):
    B, Fm = R["models"]["BIN"], R["models"]["FP"]
    L = ["# diagnose: BIN vs FP-activation preact qc18-arch (qc18b/diag/diagnose.py)", "",
         f"BIN `{R['bin']}`, FP `{R['fp']}`.  Measured.  Eval mode, fp32, TF32 off; train = train[:10000] of the 45k split "
         "(no aug), val = 5k val split.  Definitions in the script docstring.", "",
         "## Reproduction", "", "| model | rebuilt val (fp32) | rebuilt val (fp64 forward) | saved val |", "|---|---|---|---|",
         f"| BIN | {100 * B['val']:.2f} | {100 * B['val_fp64']:.2f} | {100 * B['saved_val']:.2f} |",
         f"| FP | {100 * Fm['val']:.2f} | {100 * Fm['val_fp64']:.2f} | {100 * Fm['saved_val']:.2f} |", "",
         "## D1 linear probe on GAP(relu(s)) (acc %) and linear CKA BIN vs FP", "",
         f"probe: Adam full batch {STEPS} steps, (lr, wd) from {GRID} chosen on train[8000:10000]; CKA pooled on 5k val, "
         f"unpooled (relu(s) flattened C*H*W) on val[:{NCKA}].", "",
         "| layer | BIN train | BIN val | FP train | FP val | BIN (lr, wd) | FP (lr, wd) | CKA pooled | CKA unpooled |",
         "|---|---|---|---|---|---|---|---|---|"]
    for r in R["d1"]:
        b, f = r["BIN"], r["FP"]
        L.append(f"| {r['layer']} | {100 * b['train']:.2f} | {100 * b['val']:.2f} | {100 * f['train']:.2f} | {100 * f['val']:.2f} | "
                 f"({b['lr']:g}, {b['wd']:g}) | ({f['lr']:g}, {f['wd']:g}) | {r['cka_pooled']:.3f} | {r['cka_unpooled']:.3f} |")
    L += ["", "## D2 activation-slot input u / std_c(x) (val); BIN u = x - t_c, FP u = x (ReLU input)", "",
          "| layer | model | \\|z\\|<0.1 | \\|z\\|<0.25 | \\|z\\|<0.5 | p1 min | p1 p10 | p1 med | p1 p90 | p1 max | const-x ch |",
          "|---|---|---|---|---|---|---|---|---|---|---|"]
    for rb, rf in zip(R["d2"]["BIN"], R["d2"]["FP"]):
        for tag, r in (("BIN", rb), ("FP", rf)):
            L.append(f"| {r['layer']} | {tag} | {r['lt01']:.4f} | {r['lt025']:.4f} | {r['lt05']:.4f} | {r['p1_min']:.4f} | "
                     f"{r['p1_p10']:.4f} | {r['p1_med']:.4f} | {r['p1_p90']:.4f} | {r['p1_max']:.4f} | {r['zero_std_ch']} |")
    L += ["", "## D3 QCConv2d pre-BN output (val)", "",
          "BIN block convs (recomputed in fp64, exact): integer output of {0,1} input x {-1,0,1} weights; nnz w = mean over output channels of nonzero "
          "weights (of fan-in); active = mean over output elements of #(w != 0 and input = 1).", "",
          "| layer | BIN distinct | BIN min | BIN max | BIN std | BIN frac 0 | nnz w / fan-in | active terms | FP std | BIN std / FP std |",
          "|---|---|---|---|---|---|---|---|---|---|"]
    for rb, rf in zip(R["d3"]["BIN"], R["d3"]["FP"]):
        if "distinct" in rb:
            L.append(f"| {rb['layer']} | {rb['distinct']} | {rb['min']:.0f} | {rb['max']:.0f} | {rb['std']:.3f} | {rb['zero']:.4f} | "
                     f"{rb['nnz_w']:.1f} / {rb['fanin']} | {rb['active']:.2f} | {rf['std']:.4f} | {rb['std'] / rf['std']:.2f} |")
        else:
            L.append(f"| {rb['layer']} (FP image input) | - | - | - | {rb['std']:.4f} | - | - | - | {rf['std']:.4f} | {rb['std'] / rf['std']:.2f} |")
    chk = [r for r in R["d3"]["BIN"] if "distinct" in r]
    L += ["", f"checks: all BIN block-conv inputs in {{0,1}}: {all(r['input_binary'] for r in chk)}; non-integer outputs: "
          f"{sum(r['nonint'] for r in chk)} (BIN stats from an fp64 recomputation of each conv; max |cuDNN fp32 module output - exact| "
          f"over layers {max(r['fp32err'] for r in chk):.2e}, i.e. the fp32 forward is not integer-exact)", "",
          "## D4 residual branch vs identity (val)", "", "| block | ds | BIN ratio | FP ratio | BIN cos | FP cos |", "|---|---|---|---|---|---|"]
    for rb, rf in zip(R["d4"]["BIN"], R["d4"]["FP"]):
        L.append(f"| {rb['block']} | {int(rb['ds'])} | {rb['ratio']:.3f} | {rf['ratio']:.3f} | {rb['cos']:.3f} | {rf['cos']:.3f} |")
    d = R["d5"]
    L += ["", "## D5 loss / accuracy", "", "| model | train CE | train acc | val CE | val acc |", "|---|---|---|---|---|",
          f"| BIN | {B['ce_train']:.4f} | {100 * B['train']:.2f} | {B['ce_val']:.4f} | {100 * B['val']:.2f} |",
          f"| FP | {Fm['ce_train']:.4f} | {100 * Fm['train']:.2f} | {Fm['ce_val']:.4f} | {100 * Fm['val']:.2f} |", "",
          f"per-class train acc gap FP - BIN: mean {100 * d['gap_mean']:.2f} pp; corr(gap, FP per-class train acc) "
          f"{d['corr_gap_fp']:.3f}; 5 largest (class: gap pp, FP acc %): "
          + ", ".join(f"{c}: {100 * g:.1f}, {100 * f:.1f}" for c, g, f in d["top5"]), "",
          "## D6 BatchNorm medians", "", "| layer | BIN \\|gamma\\| | FP \\|gamma\\| | BIN \\|beta\\| | FP \\|beta\\| | BIN rstd | FP rstd |",
          "|---|---|---|---|---|---|---|"]
    for rb, rf in zip(R["d6"]["BIN"], R["d6"]["FP"]):
        L.append(f"| {rb['layer']} | {rb['gamma']:.4f} | {rf['gamma']:.4f} | {rb['beta']:.4f} | {rf['beta']:.4f} | {rb['rstd']:.4f} | {rf['rstd']:.4f} |")
    with open(path, "w") as fh:
        fh.write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
