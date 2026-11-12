"""Distillation from a frozen FP-activation QC teacher, inside the student's training forward (qc18.train untouched).

attach(student, teacher, fkd=BETA, tkd=A, kd_t=T): student = binarize(..., preact=1) model, teacher = the same
preact qc18-arch QC model with act=False (FP activations), eval mode, no grad, not a registered submodule (not in
state_dict / parameters / .train()).  In every training forward (training mode, grad enabled) on the same input x:
  s_k, t_k = block k output (pre-ReLU) of student / teacher, k = 0..7;  r_k = rms(t_k) over the batch tensor (detached)
  L_f = BETA * mean_k MSE(s_k / r_k, t_k / r_k)
  L_t = A * T^2 * KL(softmax(t_logits / T) || softmax(s_logits / T))   (batchmean, as qc18.train --kd)
  aux = L_f + L_t (fp32);  forward returns AuxInject(logits, aux) = logits (values unchanged), whose backward also
  sends gradient 1 into aux, so loss.backward() in qc18.train yields d(loss + aux)/d(params).
Eval / no-grad forwards (val, BN recalibration) are the plain student.  On grad-flow logged steps one jsonl record
kind="aux" (lf, lt) is appended to the student's log file.
"""
import json

import torch
import torch.nn.functional as F

from .binact import BinQCResNet18


class AuxInject(torch.autograd.Function):
    @staticmethod
    def forward(ctx, logits, aux):
        return logits.view_as(logits)

    @staticmethod
    def backward(ctx, g):
        return g, torch.ones((), dtype=torch.float32, device=g.device)


def feats(m, x):
    """preact BinQCResNet18 forward -> (logits, [block outputs, pre-ReLU])."""
    s, fs = m.stem(x), []
    for blk in m.blocks:
        s = blk(s)
        fs.append(s)
    return m.fc(F.relu(s).mean(dim=(2, 3))), fs


class DistillQCResNet18(BinQCResNet18):
    @torch._dynamo.disable
    def forward(self, x):
        train = self.training and torch.is_grad_enabled()
        self._aux_on = train
        try:
            r = BinQCResNet18.forward(self, x)
        finally:
            self._aux_on = False
        if not train:
            return r
        out, lf, lt = r
        if self._log_path and self._pending is not None and self._pending[0] == self._calls:
            with open(self._log_path, "a") as fh:
                fh.write(json.dumps(dict(step=self._calls, epoch=(self._calls - 1) // self._spe, layer="aux", kind="aux",
                                         lf=float(lf.detach()), lt=float(lt.detach()))) + "\n")
        return AuxInject.apply(out, lf + lt)

    def _net(self, x):
        if not self._aux_on:
            return BinQCResNet18._net(self, x)
        out, fs = feats(self, x)
        with torch.no_grad():
            tout, ts = feats(self._teacher[0], x)
        lf = lt = torch.zeros((), device=out.device)
        if self._fkd:
            mse = []
            for s, t in zip(fs, ts):
                s, t = s.float(), t.float()
                r = t.pow(2).mean().sqrt()
                mse.append(F.mse_loss(s / r, t / r))
            lf = self._fkd * torch.stack(mse).mean()
        if self._tkd:
            T = self._kd_t
            lt = self._tkd * T * T * F.kl_div(F.log_softmax(out.float() / T, 1), F.log_softmax(tout.float() / T, 1),
                                              reduction="batchmean", log_target=True)
        return out, lf, lt


def attach(student, teacher, fkd=0.0, tkd=0.0, kd_t=4.0, compile=True):
    assert isinstance(student, BinQCResNet18) and student._preact and teacher._preact, "--qc-teacher needs --preact 1"
    teacher.eval().requires_grad_(False)
    student.__class__ = DistillQCResNet18
    student._teacher = [teacher]                    # list: not a registered submodule
    student._fkd, student._tkd, student._kd_t, student._aux_on = float(fkd), float(tkd), float(kd_t), False
    fwd = lambda x: student._net(x)
    student._cfwd = torch.compile(fwd) if compile else fwd
    return student
