"""CPU check of qc18b.distill:  python3 -m qc18b.test_distill
Param grads of qc18.train's loss (CE on the AuxInject logits) == autograd of CE + aux computed directly."""
import copy
import json
import os
import tempfile

import torch
import torch.nn.functional as F

from qc18.model import QCResNet18
from qc18b import distill
from qc18b.binact import binarize

torch.manual_seed(0)
ref = QCResNet18("signed", 8, num_classes=100)
for mod in ref.modules():
    if isinstance(mod, torch.nn.BatchNorm2d):
        with torch.no_grad():
            mod.running_mean.normal_(0, 0.3); mod.running_var.uniform_(0.5, 2); mod.weight.uniform_(0.5, 1.5); mod.bias.normal_(0, 0.3)
teacher = binarize(copy.deepcopy(ref), compile=False, act=False, preact=1)
with torch.no_grad():                                     # teacher != student
    for p in teacher.parameters():
        p.add_(0.1 * torch.randn_like(p))
x, y = torch.randn(4, 3, 32, 32), torch.randint(0, 100, (4,))
log = os.path.join(tempfile.mkdtemp(), "gradflow.jsonl")
for fkd, tkd, log_every in ((1.0, 0.0, 0), (0.0, 0.5, 0), (1.0, 0.5, 1)):
    st = binarize(copy.deepcopy(ref), compile=False, preact=1, k=0.6, log_path=log, log_every=log_every, spe=1)
    st = distill.attach(st, copy.deepcopy(teacher), fkd, tkd, 4.0, compile=False).train()
    st2 = copy.deepcopy(st)
    out = st(x)                                           # qc18.train path: loss value is CE only
    F.cross_entropy(out, y).backward()
    st2._aux_on = True                                    # direct: CE + aux
    o2, lf, lt = st2._net(x)
    assert torch.equal(out, o2)
    (F.cross_entropy(o2, y) + lf + lt).backward()
    st3 = copy.deepcopy(st2)                              # sanity: aux changes the grads
    st3.zero_grad(); st3._aux_on = False
    F.cross_entropy(st3._net(x), y).backward()
    eff = max(((p.grad - q.grad).abs().max() / q.grad.abs().max()).item()
              for p, q in zip(st3.parameters(), st2.parameters()) if q.grad is not None)
    assert eff > 1e-4, eff
    worst = 0.0
    for (n, p), (_, q) in zip(st.named_parameters(), st2.named_parameters()):
        assert (p.grad is None) == (q.grad is None), n
        if p.grad is not None:
            worst = max(worst, ((p.grad - q.grad).abs().max() / q.grad.abs().max().clamp_min(1e-30)).item())
    assert all(p.grad is None for p in st._teacher[0].parameters())
    assert worst < 1e-5, worst
    assert not any(k.startswith("_teacher") for k in st.state_dict())
    st.eval()
    with torch.no_grad():
        assert st(x).shape == (4, 100)                    # eval: plain logits
    print(f"fkd={fkd} tkd={tkd} log_every={log_every}: lf {lf.item():.4f} lt {lt.item():.4f}, max rel grad diff {worst:.2e} (aux effect on grads: max rel {eff:.2e})")
st.train()(x).sum().backward()                            # flush the logged step
recs = [json.loads(l) for l in open(log)]
aux = [r for r in recs if r["kind"] == "aux"]
assert aux and {"lf", "lt"} <= aux[0].keys()
print(f"gradflow aux records: {len(aux)}, first {aux[0]}")
