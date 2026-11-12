"""--bn-opt adam: optimise every BatchNorm weight / bias and every BinAct threshold t with Adam instead of the main SGD.

Hook (qc18/ is not modified): for the duration of qc18.train.main(), torch.optim.SGD is replaced by SGDBNAdam
(`patched(model_ref, lr)` context manager).  qc18.train.main builds its main optimiser as
    torch.optim.SGD([dict(params=decay, ...), dict(params=other, weight_decay=0)], lr, momentum=0.9, nesterov=True)
SGDBNAdam, when constructed with such a list of param-group dicts, removes the student's BN / threshold params from
every group (only 'other' holds them) and owns a torch.optim.Adam(those params, lr=bn_lr, betas=(0.9, 0.999),
weight_decay=0).  step() steps both; zero_grad() zeroes both.  Schedule: qc18.train attaches its LambdaLR
(linear warmup over --warmup epochs, then cosine to 0, stepped every step) to this SGD; at every step the Adam lr is
set to bn_lr * (SGD group lr / SGD group initial_lr), i.e. exactly the same multiplicative schedule factor.
Constructions with plain param lists (the theta SGD of --qopt sgd) are untouched: plain SGD behaviour.
FC weight / bias and dense conv weights stay in SGD; theta stays in its AdamW (constructed separately).
--bn-opt sgd: no patch is installed (setup identical to before)."""
import contextlib

import torch
import torch.nn as nn

from .binact import BinAct

_SGD = torch.optim.SGD


def bn_params(model):
    """all BatchNorm affine weights / biases + all BinAct thresholds t of the model (in module order, unique)."""
    out, seen = [], set()
    for m in model.modules():
        ps = [m.weight, m.bias] if isinstance(m, nn.modules.batchnorm._BatchNorm) and m.affine else \
             [m.t] if isinstance(m, BinAct) else []
        for p in ps:
            if id(p) not in seen:
                seen.add(id(p))
                out.append(p)
    return out


def make_sgd_cls(model_ref, bn_lr):
    """model_ref: list that holds the student model once it is built (before the optimiser is constructed)."""

    class SGDBNAdam(_SGD):
        def __init__(self, params, *args, **kw):
            params = list(params)
            self.bn_adam = None
            if params and isinstance(params[0], dict):           # the main grouped SGD of qc18.train.main
                assert len(model_ref) == 1, "student model not registered"
                bn = bn_params(model_ref[0])
                ids = {id(p) for p in bn}
                params = [dict(g, params=[p for p in g["params"] if id(p) not in ids]) for g in params]
                n_in = sum(len(g["params"]) for g in params)
                self.bn_adam = torch.optim.Adam(bn, lr=bn_lr, betas=(0.9, 0.999), weight_decay=0.0)
                self.bn_lr = bn_lr
                names = ["decay", "other"] + [f"g{i}" for i in range(2, len(params))]
                cnt = lambda ps: (len(ps), sum(p.numel() for p in ps))
                print("bn-opt adam: " + "  ".join(f"SGD[{n}] {cnt(g['params'])[0]} tensors / {cnt(g['params'])[1]} "
                                                  "params" for n, g in zip(names, params))
                      + f"  Adam[bn+t] {cnt(bn)[0]} tensors / {cnt(bn)[1]} params (lr {bn_lr})"
                      + "  AdamW[theta] {} tensors / {} params".format(*cnt(
                          [p for n, p in model_ref[0].named_parameters() if n.endswith("theta")])), flush=True)
                assert n_in > 0
            super().__init__(params, *args, **kw)

        def zero_grad(self, set_to_none=True):
            super().zero_grad(set_to_none=set_to_none)
            if self.bn_adam is not None:
                self.bn_adam.zero_grad(set_to_none=set_to_none)

        def step(self, closure=None):
            loss = super().step(closure)
            if self.bn_adam is not None:
                g = self.param_groups[0]
                f = g["lr"] / g["initial_lr"] if "initial_lr" in g else 1.0
                for ag in self.bn_adam.param_groups:
                    ag["lr"] = self.bn_lr * f
                self.bn_adam.step()
            return loss

    return SGDBNAdam


@contextlib.contextmanager
def patched(model_ref, bn_lr):
    torch.optim.SGD = make_sgd_cls(model_ref, bn_lr)
    try:
        yield
    finally:
        torch.optim.SGD = _SGD
