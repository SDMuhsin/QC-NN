"""Snapshot support for qc18.train (--snap 1; measurement only, training unchanged).

<out>/snap/v_ep{E:03d}.pt   hard v (int8, list over model.qconvs()) at the end of epoch E (1-based; E=0: init)
<out>/snap/ckpt_ep{E:03d}.pt full checkpoint at the end of the epochs in --snap-ckpt (1-based)
<out>/snap/steps_ep{E:03d}.pt during the epochs in --snap-steps (1-based): dict(steps=[0, k, 2k, ...],
                              v=[snapshot per step]), hard(theta) after that many optimizer steps of epoch E
                              (step 0 = start of the epoch = v_ep{E-1}), k = --snap-every
"""
import os

import torch

from ..qcconv import hard, row_alpha


def ints(s):
    return {int(t) for t in s.split(",") if t}


@torch.no_grad()
def hard_v(model):
    """Current hard(theta) of every conv as int8 CPU tensors (does not touch the stored buffer v)."""
    return [hard(c.theta, row_alpha(c.theta), c.signed).to(torch.int8).cpu() for c in model.qconvs()]


class Snapper:
    def __init__(self, a, model):
        self.on, self.model = bool(a.snap), model
        if not self.on:
            return
        self.dir = os.path.join(a.out, "snap")
        os.makedirs(self.dir, exist_ok=True)
        self.ckpt, self.steps, self.every = ints(a.snap_ckpt), ints(a.snap_steps), a.snap_every
        self.cur = None
        torch.save(hard_v(model), os.path.join(self.dir, "v_ep000.pt"))

    def epoch_start(self, ep):
        if self.on and ep + 1 in self.steps:
            self.cur = dict(steps=[0], v=[hard_v(self.model)])

    def step(self, ep, i):
        """Call after optimizer step i (0-based) of epoch ep (0-based)."""
        if self.on and self.cur is not None and (i + 1) % self.every == 0:
            self.cur["steps"].append(i + 1)
            self.cur["v"].append(hard_v(self.model))

    def epoch_end(self, ep, save):
        if not self.on:
            return
        E = ep + 1
        torch.save([c.v.to(torch.int8).cpu() for c in self.model.qconvs()], os.path.join(self.dir, f"v_ep{E:03d}.pt"))
        if self.cur is not None:
            torch.save(self.cur, os.path.join(self.dir, f"steps_ep{E:03d}.pt"))
            self.cur = None
        if E in self.ckpt:
            save(os.path.join(self.dir, f"ckpt_ep{E:03d}.pt"))
