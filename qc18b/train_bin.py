"""qc18b.train (CIFAR-100 qc18.train) with binary activations (qc18b.binact) on every non-stem QCConv2d input.
Extra options (stripped before qc18.train parses argv):
  --binact 0|1  --ste clip|approx|bussgang|stein  --ste-w W  --ste-scale K  --t-train 0|1  --bin-stem 0  --preact 0|1 (B1 reads the pre-ReLU block input, binact.py)  --arch qc18|bireal (needs --preact 1)  --stem-therm K (0: FP stem input; K>0: stem reads a 3K-plane thermometer code, binact.therm_stem)  --fp-blocks LIST (comma block indices 0..7 with ReLU instead of BinAct b1/b2)  --init CKPT (FP-act checkpoint, loaded before training;
  BinAct thresholds stay 0)  --qc-teacher CKPT --fkd BETA --tkd A --atkd B (frozen FP-activation preact QC teacher from a qc18b
  QC checkpoint; block-output feature / logit / larq_zoo attention-map distillation added in the student's training forward, qc18b.distill;
  T = --kd-t)  --prog H (binact 1: progressive binarisation over the first H of the training steps, binact.set_prog;
  per-epoch p -> <out>/prog.jsonl; best_hard.pt = best val among epochs whose steps all had p = 1)  --log-every K (grad-flow jsonl -> <out>/gradflow.jsonl)
  --bn-opt sgd|adam --bn-lr LR (adam: BN weight/bias + BinAct t in a separate Adam, same warmup+cosine shape; qc18b.bnopt)
    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.train_bin --binact 1 --mode signed --b 8 --epochs 60 --out DIR"""
import argparse
import inspect
import json
import os
import sys

import torch

import qc18.model
import qc18.train

from . import binact, bnopt, c100, data, distill

if __name__ == "__main__":
    p = argparse.ArgumentParser(allow_abbrev=False)
    p.add_argument("--binact", type=int, default=1)
    p.add_argument("--ste", default="clip", choices=["clip", "approx", "bussgang", "stein"])
    p.add_argument("--ste-w", type=float, default=1.0)
    p.add_argument("--ste-scale", type=float, default=1.0)
    p.add_argument("--t-train", type=int, default=1)
    p.add_argument("--bin-stem", type=int, default=0)
    p.add_argument("--preact", type=int, default=0)
    p.add_argument("--arch", default="qc18", choices=["qc18", "bireal"])
    p.add_argument("--stem-therm", type=int, default=0)
    p.add_argument("--fp-blocks", default="")
    p.add_argument("--init", default="")
    p.add_argument("--log-every", type=int, default=50)
    p.add_argument("--qc-teacher", default="")
    p.add_argument("--fkd", type=float, default=0.0)
    p.add_argument("--tkd", type=float, default=0.0)
    p.add_argument("--atkd", type=float, default=0.0)
    p.add_argument("--prog", type=float, default=0.0)
    p.add_argument("--bn-opt", default="sgd", choices=["sgd", "adam"])
    p.add_argument("--bn-lr", type=float, default=1e-3)
    x, rest = p.parse_known_args()
    q = argparse.ArgumentParser(add_help=False, allow_abbrev=False)   # read (not stripped) the qc18.train options binarize needs
    q.add_argument("--out", default="")
    q.add_argument("--bs", type=int, default=128)
    q.add_argument("--compile", type=int, default=1)
    q.add_argument("--kd-t", type=float, default=4.0)
    q.add_argument("--epochs", type=int, default=200)
    a, _ = q.parse_known_args(rest)
    assert a.out, "--out required"
    sys.argv = sys.argv[:1] + rest
    c100.apply()
    base = qc18.train.QCResNet18                   # c100's num_classes=100 factory

    assert not (x.fkd or x.tkd or x.atkd) or x.qc_teacher, "--fkd / --tkd / --atkd need --qc-teacher"
    assert not x.prog or (x.binact and 0 < x.prog <= 1), "--prog needs --binact 1, 0 < H <= 1"
    spe = 45000 // a.bs
    student = []
    model_ref = []                                 # the student (first non-dense model built), for --bn-opt

    def factory(*args, **kw):
        m = base(*args, **kw)
        if m.mode == "dense":                      # KD teacher (and --mode dense) stay plain
            return m
        if x.stem_therm:
            q = inspect.signature(qc18.model.QCResNet18).bind(*args, **kw)
            q.apply_defaults()
            q = dict(q.arguments)
            qc = dict(mode=q["mode"], b=q["b"], estimator=q["estimator"], tau=q["tau"], relax=q["relax"],
                      qinit_scale=q["qinit_scale"], homotopy=q["homotopy"])
            m = binact.therm_stem(m, x.stem_therm, data.MEAN, data.STD, **qc)
        os.makedirs(a.out, exist_ok=True)              # binact 0: FP activations, same logging forward
        m = binact.binarize(m, x.ste, x.ste_w, x.bin_stem, os.path.join(os.path.abspath(a.out), "gradflow.jsonl"),
                            x.log_every, 45000 // a.bs, bool(a.compile), act=bool(x.binact),
                            k=x.ste_scale, t_train=x.t_train, preact=x.preact, arch=x.arch,
                            fp_blocks=tuple(int(i) for i in x.fp_blocks.split(",") if i))
        if not model_ref:
            model_ref.append(m)
        if x.prog:
            binact.set_prog(m, round(x.prog * a.epochs * spe))
            student.append(m)
        if x.init:
            sd = torch.load(x.init, map_location="cpu")["state"]
            missing, unexpected = m.load_state_dict(sd, strict=False)
            assert not unexpected and all(k.endswith((".b1.t", ".b2.t")) for k in missing), (missing, unexpected)
            print(f"init {x.init}: {len(sd)} tensors, {len(missing)} BinAct thresholds left at 0", flush=True)
        if x.qc_teacher:
            ck = torch.load(x.qc_teacher, map_location="cpu")
            assert (ck["args"]["mode"], ck["args"]["b"]) == (m.mode, m.blocks[0].c1.conv.b), ck["args"]
            t = binact.binarize(base(*args, **kw), compile=False, act=False, preact=1)   # FP-act preact qc18, no logging
            t.load_state_dict(ck["state"])
            t = t.cuda().to(memory_format=torch.channels_last)        # the student is moved to cuda by qc18.train
            distill.attach(m, t, x.fkd, x.tkd, a.kd_t, bool(a.compile), atkd=x.atkd)
            print(f"qc teacher {x.qc_teacher} (val {100 * ck['val']:.2f}) fkd={x.fkd} tkd={x.tkd} atkd={x.atkd} T={a.kd_t}", flush=True)
        print(f"binact={x.binact} ste={x.ste} w={x.ste_w} K={x.ste_scale} t_train={x.t_train} bin_stem={x.bin_stem} preact={x.preact} arch={x.arch} stem_therm={x.stem_therm} fp_blocks={x.fp_blocks}", flush=True)
        return m

    qc18.train.QCResNet18 = factory
    acc0, best = qc18.train.accuracy, [-1.0, -1]

    def accuracy(model, *args, **kw):              # --prog: per-epoch p log, best_hard.pt among p = 1 epochs
        va = acc0(model, *args, **kw)
        if student and model is student[0] and model._calls % spe == 0 and model._calls:
            ep = model._calls // spe - 1
            ps = model._prog_p[ep * spe:(ep + 1) * spe]
            hard = min(ps) == 1.0
            if hard and va > best[0]:
                best[:] = [va, ep]
                torch.save(dict(args=dict(argv=sys.argv, **vars(x)), state=model.state_dict(), epoch=ep, val=va),
                           os.path.join(a.out, "best_hard.pt"))
            with open(os.path.join(a.out, "prog.jsonl"), "a") as fh:
                fh.write(json.dumps(dict(epoch=ep, p_first=ps[0], p_last=ps[-1], p_mean=sum(ps) / len(ps), hard=hard,
                                         val=va, best_hard=best[0], best_hard_epoch=best[1])) + "\n")
            print(f"prog ep {ep}: p {ps[0]:.4f}..{ps[-1]:.4f}  hard {hard}  best_hard {100 * best[0]:.2f}@{best[1]}", flush=True)
        return va

    qc18.train.accuracy = accuracy
    if x.bn_opt == "adam":
        with bnopt.patched(model_ref, x.bn_lr):
            qc18.train.main()
    else:
        qc18.train.main()
