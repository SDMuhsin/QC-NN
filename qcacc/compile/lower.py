"""Lower an s2 (per-output-channel requant, ternary QC weights) network to the KUL cluster.

Reuses nn/compile/lower.py (tensor layout, implicit-im2col streamer CSRs, liveness allocator,
nn_conv_t image, add / pool+FC steps).  Differences:
  * one GeMMX call per 8-output-channel group (N = 1; the RescaleSIMD has 8 lanes and s2 has one
    multiplier/shift per output channel).  Each call is its own runtime step whose
    output is a one-group view "convX_gG" of the conv's tensor (plane g), so nn/sw/nn_cluster.c runs it
    unchanged and checks every group.  One blob per conv holds, per group:
        [B tiles of the group][bias tile 256 B][nn_conv_t]   (each part 64 B aligned)
  * mode "gemmx": B = the int8 ternary weights, GeMMX B layout [ci8][kh][kw][8 co][8 ci] (control).
  * mode "qc":    B = one 64-bit QC code word per 8x8 tile (qcacc.model.codec), same tile order;
    rows flipped by the encoder store M, their bias and SIMD multiplier are negated.
    B streamer (1 channel x 64 b): Bslstride0 = 1, Bslstride1 = 0, Btlbound0 = K, Btlstride0 = 8,
    Btlbound1 = N (= 1), Btlstride1 = 8 K, Btlbound2 = M, Btlstride2 = 0.
"""
from types import SimpleNamespace

import numpy as np

from nn.compile.lower import (CONV_PARAM_BYTES, ORDER, SHAPES, TCDM_RESERVED, TCDM_SIZE, Blob, Step,
                              Tensor, add_lut, allocate, conv_blob, conv_params, gemmx_cfg, pad64)
from nn.model.resnet8 import CONV_CFG
from nn.quant.quantize import ADDS, CONV_IN

from ..model.codec import encode_conv

MODES = ("gemmx", "qc")


def parent(name):
    return name.split("_g")[0]


def qc_chunk(codes_g, bias_g):
    """One group of a QC conv blob: codes [ci8, k, k] uint64 -> (bytes, offset of the bias tile)."""
    b = pad64(codes_g.astype("<u8").tobytes())
    bias = np.repeat(np.asarray(bias_g, np.int64).astype(np.int32).reshape(1, 8), 8, axis=0)
    return b + bias.tobytes() + pad64(bytes(CONV_PARAM_BYTES)), len(b)


class QCProgram:
    """Same interface as nn.compile.lower.Program (tensors, steps, blobs, arena, peak, input_image,
    macs), so nn.compile.emit / schedule_sim.run_image / cycle_estimate work on it."""

    def __init__(self, q, mode):
        assert mode in MODES
        self.q, self.mode = q, mode
        act = q["act"]
        self.tensors = {n: Tensor(n, C, H, act[n][1]) for n, (C, H) in SHAPES.items()}
        for n, src in CONV_IN.items():
            if CONV_CFG[n][3] == 3:
                self.tensors[src].border = True
        self.steps, self.blobs, self.sigma, self.chunks = [], [], {}, {}
        for n in ORDER:
            i = len(self.steps)
            if n == "input":
                self.steps.append(Step(i, "input", n, [], n))
            elif n.startswith("conv"):
                blob = self._conv_blob(n)
                for g in range(len(self.chunks[n])):
                    self.steps.append(Step(i + g, "conv", f"{n}_g{g}", [CONV_IN[n]], f"{n}_g{g}", blob,
                                           dict(conv=n, group=g)))
            elif n.startswith("add"):
                cfg = dict(q["add"][n])
                self.steps.append(Step(i, "add", n, list(ADDS[n]), n, add_lut(n, cfg), cfg))
            else:
                fc = q["fc"]
                wb = pad64(fc["W"].astype(np.int8).tobytes())
                data = wb + pad64(fc["bias"].astype(np.int32).tobytes())
                self.steps.append(Step(i, "poolfc", n, ["add3"], None, Blob("w_fc", data),
                                       dict(zp_in=fc["zp_in"], bias_off=len(wb))))
        # liveness (on the real tensors); a conv's blob is prefetched at the first step of the previous blob
        prev, seen = 0, set()
        for st in self.steps:
            if st.out:
                t = self.tensors[parent(st.out)]
                t.live = [min(t.live[0], st.idx), max(t.live[1], st.idx)]
            for n in st.ins:
                self.tensors[n].live[1] = max(self.tensors[n].live[1], st.idx)
            if st.blob:
                if id(st.blob) in seen:
                    st.blob.live[1] = st.idx
                else:
                    seen.add(id(st.blob))
                    st.blob.issue, st.blob.live = prev, [prev, st.idx]
                    prev = st.idx
                    self.blobs.append(st.blob)
        self.arena = TCDM_SIZE - TCDM_RESERVED
        self.peak = allocate(list(self.tensors.values()) + self.blobs, self.arena)
        # one-group views of the conv outputs (not allocated: plane g of the real tensor)
        for st in self.steps:
            if st.kind == "conv":
                t, g = self.tensors[st.cfg["conv"]], st.cfg["group"]
                v = Tensor(st.out, 8, t.H, t.zp, t.border)
                v.addr, v.live = t.addr + g * t.plane, list(t.live)
                self.tensors[st.out] = v
                self._call_cfg(st)

    def _conv_blob(self, n):
        v = self.q["conv"][n]
        W = np.asarray(v["W"], np.int64)
        G = W.shape[0] // 8
        if self.mode == "qc":
            codes, sig = encode_conv(W)
        else:
            sig = np.ones(W.shape[0], np.int64)
        self.sigma[n] = sig
        data, chunks = b"", []
        for g in range(G):
            sl = slice(8 * g, 8 * g + 8)
            if self.mode == "qc":
                d, wsize = qc_chunk(codes[g], sig[sl] * np.asarray(v["bias"])[sl])
            else:
                b, wsize = conv_blob(n, dict(W=W[sl], bias=np.asarray(v["bias"])[sl]))
                d = b.data
            chunks.append((len(data), wsize))
            data += d
        self.chunks[n] = chunks
        return Blob("w_" + n, data)

    def _call_cfg(self, st):
        n, g = st.cfg["conv"], st.cfg["group"]
        v, sl = self.q["conv"][n], slice(8 * st.cfg["group"], 8 * st.cfg["group"] + 8)
        off, wsize = self.chunks[n][g]
        vg = dict(zp_in=v["zp_in"], zp_out=v["zp_out"], hi=v["hi"], lo=v["lo"],
                  shift=np.asarray(v["shift"])[sl], mult=self.sigma[n][sl] * np.asarray(v["mult"])[sl])
        assert np.all(np.abs(vg["mult"]) < 2 ** 31)
        c = gemmx_cfg(n, vg, self.tensors[st.ins[0]], self.tensors[st.out], wsize,
                      SimpleNamespace(addr=st.blob.addr + off))
        if self.mode == "qc":
            c.update(Bslstride0=1, Bslstride1=0, Btlstride0=8, Btlstride1=8 * c["K"], qc=1)
        c["wsize"] = off + wsize                 # blob offset of the bias tile (nn.compile.emit)
        st.cfg.update(c)
        po = c["wsize"] + 256
        pb = conv_params(c)
        st.blob.data = st.blob.data[:po] + pb + st.blob.data[po + len(pb):]

    def input_image(self, x_q):
        return self.tensors["input"].pack(np.asarray(x_q))

    def calls(self):
        return sum(st.kind == "conv" for st in self.steps)

    def macs(self):
        """(useful MACs, GeMMX fires) per image."""
        useful = fires = 0
        for st in self.steps:
            if st.kind == "conv":
                if st.cfg["group"] == 0:
                    useful += self.q["conv"][st.cfg["conv"]]["W"].size * self.tensors[st.out].H ** 2
                fires += st.cfg["M"] * st.cfg["N"] * st.cfg["K"]
        return useful, fires

    def weight_bytes(self):
        """B tile bytes (without bias tiles / nn_conv_t) per image."""
        return sum(w for ch in self.chunks.values() for _, w in ch)
