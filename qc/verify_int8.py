"""Prove that the int8 weights produced by nn.quant.quantize are exactly the QC matrices:

    python -m qc.verify_int8 CKPT QPARAMS      (QPARAMS from --params <qc.export npz> --wgran channel --wq 1)

Per conv: the int8 weights must be in {-1, 0, 1} and equal sign(s_co) * M_co (the BN-scale sign is
folded into the weights by --wgran channel --wq 1; d_co = sign(s_co) comes from the checkpoint, +1 if
s_co = 0).  d * W_int8 is laid out as the GEMM matrix (structure.to_matrix) and every b x b block is
decomposed with structure.decompose.  W_int8 has no padded input channels (conv0, cin 3): those columns
are taken from the checkpoint matrix (they multiply the zero-padded channels, so they never contribute).
Also checks the requant scale sw_co = |s_co| (or the REAL_MIN floor; any value for an all-zero int8 row,
e.g. conv0 rows whose nonzeros all sit in the padded channels).  Exits 1 on any failure.
"""
import sys

import numpy as np
import torch

from nn.model.resnet8 import CONVS
from nn.quant.quantize import CONV_IN, REAL_MIN

from .structure import cin_pad, decompose, expand, to_matrix
from .verify import fold, load


@torch.no_grad()
def main(ckpt, qpath):
    ck = torch.load(ckpt, map_location="cpu")
    q = torch.load(qpath, map_location="cpu", weights_only=False)
    model, signed = load(ck), ck["args"]["mode"] == "signed"
    print(f"{ckpt} + {qpath}: mode {ck['args']['mode']}, int8 test {100 * q['meta']['acc_int8']:.2f} %")
    ok = True
    for n, *_ in CONVS:
        conv, v = model.conv[n], q["conv"][n]
        try:
            Wq = np.asarray(v["W"])
            assert np.isin(Wq, (-1, 0, 1)).all(), "int8 weights not in {-1,0,1}"
            scale, _ = fold(model.bn[n])
            d = torch.where(scale < 0, -1.0, 1.0).double()
            Mq = to_matrix(torch.as_tensor(Wq, dtype=torch.float64) * d[:, None, None, None], conv.b, conv.view)
            Mc = conv.matrix().double()
            real = to_matrix(torch.ones(1, conv.cin, conv.k, conv.k, dtype=torch.float64), conv.b, conv.view)[0] > 0
            assert torch.equal(Mq[:, real], Mc[:, real]), "int8 weights != sign(s) * QC matrix"
            Mq[:, ~real] = Mc[:, ~real]
            C = decompose(Mq, conv.b, signed=signed)
            assert torch.equal(expand(torch.as_tensor(C, dtype=Mq.dtype), conv.b), Mq), "re-expansion differs"
            s_in, s_out = q["act"][CONV_IN[n]][0], q["act"][n][0]
            sw, want = np.asarray(v["sw"]), scale.abs().numpy()
            live = np.abs(Wq).reshape(len(Wq), -1).any(1)          # all-zero rows: sw is a don't-care
            floored = live & (sw > want * (1 + 1e-9))
            ok_s = live & ~floored
            assert np.allclose(sw[ok_s], want[ok_s], rtol=1e-9, atol=0), "sw != |BN scale|"
            assert np.allclose(sw[floored], REAL_MIN * s_out / s_in, rtol=1e-9), "sw floor"
            res = f"PASS  ({int((d < 0).sum())} sign-flipped rows, {int(floored.sum())} floored scales, {int((~live).sum())} zero rows)"
        except (ValueError, AssertionError) as e:
            ok, res = False, f"FAIL  {e}"
        print(f"{n:6s} b {conv.b}  int8 {tuple(Wq.shape)} -> matrix {tuple(Mc.shape)}  {res}")
    print("VERIFY INT8", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
