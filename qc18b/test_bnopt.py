"""--bn-opt check (GPU, data loaded, no training):  CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.test_bnopt
Runs qc18b.train_bin in a child process per mode and stops it at the first LambdaLR (right after the main SGD is
built); records which optimiser group owns every model parameter.  Checks: groups disjoint and covering all trainable
params; adam: Adam set == BN weight/bias + BinAct t, SGD 'decay' unchanged, SGD 'other' = sgd-mode 'other' minus
the Adam set, Adam lr follows the SGD schedule factor; sgd: plain torch.optim.SGD, same groups as qc18.train."""
import json
import os
import runpy
import subprocess
import sys
import tempfile

ARGS = ["--mode", "signed", "--b", "8", "--estimator", "ste", "--qwd", "0.1", "--binact", "1", "--preact", "1",
        "--arch", "qc18", "--ste", "clip", "--epochs", "100", "--seed", "0", "--compile", "0", "--test", "0"]


class Stop(Exception):
    pass


def child(mode, out):
    import torch
    import qc18b.binact as binact
    rec = {}
    b0 = binact.binarize

    def binarize(*a, **kw):
        m = b0(*a, **kw)
        rec.setdefault("model", m)
        return m

    binact.binarize = binarize

    class LL(torch.optim.lr_scheduler.LambdaLR):
        def __init__(self, opt, *a, **kw):
            super().__init__(opt, *a, **kw)
            rec["opt"], rec["sched"] = opt, self
            raise Stop

    torch.optim.lr_scheduler.LambdaLR = LL
    sys.argv = ["train_bin"] + ARGS + ["--bn-opt", mode, "--out", out]
    try:
        runpy.run_module("qc18b.train_bin", run_name="__main__")
    except Stop:
        pass
    m, opt, sched = rec["model"], rec["opt"], rec["sched"]
    owner = {}
    for gi, g in enumerate(opt.param_groups):
        for p in g["params"]:
            owner.setdefault(id(p), []).append(f"sgd{gi}")
    bad = getattr(opt, "bn_adam", None)
    if bad is not None:
        for p in bad.param_groups[0]["params"]:
            owner.setdefault(id(p), []).append("adam")
    res = dict(cls=type(opt).__module__ + "." + type(opt).__qualname__,
               defaults={k: v for k, v in opt.defaults.items() if isinstance(v, (int, float, bool))},
               groups=[{k: v for k, v in g.items() if k != "params" and isinstance(v, (int, float, bool))}
                       for g in opt.param_groups], params={})
    for n, p in m.named_parameters():
        o = owner.get(id(p), []) + (["theta"] if n.endswith("theta") else [])
        bn = n.endswith((".b1.t", ".b2.t")) or ".bn." in n or n.startswith("bn.")
        res["params"][n] = dict(owner=o, grad=p.requires_grad, bnt=bn)
    if bad is not None:                               # schedule factor: run a few steps with zero grads
        for i in range(5):                            # [SGD factor used by this step, Adam lr used by this step]
            g = opt.param_groups[0]
            f = g["lr"] / g["initial_lr"]
            opt.step()
            res.setdefault("lr", []).append([f, bad.param_groups[0]["lr"]])
            sched.step()
    res["n_bn_modules"] = sum(1 for x in m.modules() if isinstance(x, torch.nn.modules.batchnorm._BatchNorm))
    json.dump(res, open(os.path.join(out, "probe.json"), "w"))


def main():
    r = {}
    for mode in ("sgd", "adam"):
        d = tempfile.mkdtemp()
        subprocess.run([sys.executable, "-m", "qc18b.test_bnopt", "--child", mode, d], check=True)
        r[mode] = json.load(open(os.path.join(d, "probe.json")))
    s, a = r["sgd"], r["adam"]
    assert s["cls"] == "torch.optim.sgd.SGD", s["cls"]
    for mode, x in r.items():
        for n, v in x["params"].items():
            if v["grad"]:
                assert len(v["owner"]) == 1, (mode, n, v)    # disjoint and covering
    for n, v in s["params"].items():
        assert v["owner"] in (["sgd0"], ["sgd1"], ["theta"]), (n, v)
    for n, v in a["params"].items():
        exp = ["adam"] if v["bnt"] else s["params"][n]["owner"]
        assert v["owner"] == exp, (n, v, exp)
    assert s["groups"] == a["groups"] and s["defaults"] == a["defaults"], (s["groups"], a["groups"])
    for f, lr in a["lr"]:
        assert abs(lr - 1e-3 * f) < 1e-12, a["lr"]
    cnt = lambda x, o: sum(1 for v in x["params"].values() if v["owner"] == [o])
    nbt = sum(v["bnt"] for v in a["params"].values())
    print(f"OK  sgd: SGD[decay] {cnt(s, 'sgd0')} SGD[other] {cnt(s, 'sgd1')} theta {cnt(s, 'theta')} tensors | "
          f"adam: SGD[decay] {cnt(a, 'sgd0')} SGD[other] {cnt(a, 'sgd1')} Adam {cnt(a, 'adam')} theta "
          f"{cnt(a, 'theta')} | BN+t tensors {nbt} ({a['n_bn_modules']} BN modules) | adam lr/factor {a['lr'][:2]}")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--child":
        child(sys.argv[2], sys.argv[3])
    else:
        main()
