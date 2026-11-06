"""Lower the quantized ResNet-8 to a KUL-cluster schedule: layouts, GeMMX calls, TCDM plan.

Mapping (one GeMMX call per conv, the streamer's native implicit-im2col conv mode, as in
snax_cluster sw/apps/snax-gemmx-conv):
  * every activation tensor lives in TCDM as C8HW8 with a zero-point border:
        [C/8][H+2][W+8][8] int8 (+ one 64 B tail)   (8 channels = one 64-bit word per pixel)
    The interior starts at column X0 = 8 of row 1, so every D8 output tile (8 pixels x 8 ch =
    64 B) and every row start is 64 B aligned: the GeMMX D8 writer drops address bits [5:0]
    (measured in RTL).  Column 7 is the left border; the right border of a row is column 0 of
    the next row (the tail covers the last row).  The border holds the tensor's zero point, so
    the A reader sees Keras zero padding.  3x3 stride-1 convs start the window at padded
    (0, X0-1); Keras stride-2 'same' pads only bottom/right, so 3x3/s2 and 1x1/s2 convs start at
    (1, X0).
  * A (8 output pixels of one row x 8 input channels per fire): temporal loops
    Kw, Kh, Cin/8 (K) | Cout/8 (N, stride 0) | Wo/8, Ho (M); spatial stride 8*stride.
  * B (weights) [Cout/8][Cin/8][Kh][Kw][8 co][8 ci], loops K | N | M (stride 0).
  * C (bias) one 256 B int32 tile per Cout/8 group (8 rows x 8 ch, broadcast reader), M stride 0.
  * D8 written straight into the interior of the next padded buffer (SIMD requant + ReLU).
  * Residual add (+requant, clamp by a DMA'd lookup table), avgpool+FC: Snitch cores, rows split
    between core 0 and core 1.
  * Weights (+bias tiles) are DMA'd from the memory island by core 1 (Snitch iDMA), one
    conv ahead; all buffers are placed by a liveness-based first-fit allocator.
"""
from dataclasses import dataclass, field

import numpy as np

from ..model.resnet8 import CONV_CFG
from ..quant.hw import ADD_SHIFT
from ..quant.quantize import ADDS, CONV_IN

TCDM_SIZE = 128 * 1024
TCDM_RESERVED = 4 * 1024          # top of TCDM: mailbox + core stacks (nn/sw/nn_cluster.c)
ALIGN = 64
GEMMX_OVERHEAD = 120              # est. cycles per call: CSR programming + start + drain

ORDER = ["input", "conv0", "conv1", "conv2", "add1", "conv3", "conv5", "conv4", "add2",
         "conv6", "conv8", "conv7", "add3", "poolfc"]
SHAPES = {"input": (3, 32), "conv0": (16, 32), "conv1": (16, 32), "conv2": (16, 32), "add1": (16, 32),
          "conv3": (32, 16), "conv4": (32, 16), "conv5": (32, 16), "add2": (32, 16),
          "conv6": (64, 8), "conv7": (64, 8), "conv8": (64, 8), "add3": (64, 8)}


@dataclass
class Tensor:
    name: str
    C: int
    H: int
    zp: int
    border: bool = False           # border must hold zp (read by a 3x3 conv)
    addr: int = -1
    live: list = field(default_factory=lambda: [10 ** 9, -1])

    X0 = 8                         # interior column offset (64 B aligned rows and D8 tiles)

    @property
    def C8(self): return -(-self.C // 8)
    @property
    def Hp(self): return self.H + 2            # rows incl. top/bottom border
    @property
    def Wq(self): return self.H + self.X0      # row pitch in pixels (W + 8, W % 8 == 0)
    @property
    def plane(self): return self.Hp * self.Wq * 8
    @property
    def size(self): return self.C8 * self.plane + 64

    def offset(self, c8, row, col):
        """Byte offset of padded pixel (row, col) of channel group c8 (interior: rows 1..H, cols X0..)."""
        return ((c8 * self.Hp + row) * self.Wq + col) * 8

    @property
    def origin(self):
        """Byte offset of interior pixel (0, 0) of group 0."""
        return self.offset(0, 1, self.X0)

    def view(self, mem, base=None):
        a = self.addr if base is None else base
        return mem[a:a + self.C8 * self.plane].view(np.int8).reshape(self.C8, self.Hp, self.Wq, 8)

    def interior(self, mem):
        """Read back [C8][H][W][8] int8 from a TCDM image."""
        return self.view(mem)[:, 1:-1, self.X0:self.X0 + self.H, :]

    def pack(self, x):
        """NCHW (1 image) int -> TCDM bytes of this tensor, border / extra channels / tail = zp."""
        b = np.full(self.size, self.zp, dtype=np.int8)
        self.view(b, 0)[:, 1:-1, self.X0:self.X0 + self.H, :] = to_c8hw8(x, self.C8, self.zp)[:, 1:-1, 1:-1, :]
        return b.tobytes()


@dataclass
class Blob:
    """Constant data in the memory island, DMA'd to TCDM before its step."""
    name: str
    data: bytes
    issue: int = 0                 # step at whose start the DMA is issued
    addr: int = -1
    live: list = field(default_factory=lambda: [0, 0])

    @property
    def size(self): return len(self.data)


@dataclass
class Step:
    idx: int
    kind: str                      # input | conv | add | poolfc
    name: str
    ins: list
    out: str = None
    blob: Blob = None
    cfg: dict = None               # conv: GeMMX / streamer parameters; add/poolfc: core params


def to_c8hw8(x, C8, zp):
    """NCHW (1 image) int -> padded [C8][H+2][W+2][8] int8 bytes, border/extra channels = zp."""
    C, H, W = x.shape
    t = np.full((C8 * 8, H + 2, W + 2), zp, dtype=np.int8)
    t[:C, 1:-1, 1:-1] = x
    return np.ascontiguousarray(t.reshape(C8, 8, H + 2, W + 2).transpose(0, 2, 3, 1))


def pad64(b):
    return b + bytes(-len(b) % ALIGN)


def conv_blob(name, v):
    """Weights in GeMMX B order + one 256 B bias tile per Cout/8 group."""
    W = v["W"]
    cout, cin, k, _ = W.shape
    ci8 = -(-cin // 8)
    Wp = np.zeros((cout, ci8 * 8, k, k), dtype=np.int8)
    Wp[:, :cin] = W
    B = Wp.reshape(cout // 8, 8, ci8, 8, k, k).transpose(0, 2, 4, 5, 1, 3)  # co8 ci8 kh kw co ci
    bias = np.repeat(v["bias"].astype(np.int32).reshape(cout // 8, 1, 8), 8, axis=1)
    b = B.tobytes()
    assert len(b) % ALIGN == 0
    return Blob(name, b + bias.tobytes() + pad64(bytes(CONV_PARAM_BYTES))), len(b)   # params: see conv_params


def add_lut(name, v):
    """Clamp table of a residual add on the cores (nn_cluster.c add_rows).  With the zero points,
    the rounding constant and zo folded into kc, t = (a*ma + b*mb + kc) >> 16 has a range fixed
    by int8 a, b; out = lut[t - tmin] = clamp(t, lo, 127) replaces the compare/branch clamp."""
    ma, mb = v["ma"], v["mb"]
    kc = (1 << (ADD_SHIFT - 1)) + v["zo"] * (1 << ADD_SHIFT) - v["za"] * ma - v["zb"] * mb
    ext = lambda m, f: f(-128 * m, 127 * m)
    tmin = (ext(ma, min) + ext(mb, min) + kc) >> ADD_SHIFT
    tmax = (ext(ma, max) + ext(mb, max) + kc) >> ADD_SHIFT
    v.update(kc=kc, tmin=tmin)
    lut = np.clip(np.arange(tmin, tmax + 1), v["lo"], 127).astype(np.int8)
    return Blob("lut_" + name, pad64(lut.tobytes()))


STREAMER_FIELDS = (
    "Aslstride0 Aslstride1 Atlbound0 Atlstride0 Atlbound1 Atlstride1 Atlbound2 Atlstride2 Atlbound3 "
    "Atlstride3 Atlbound4 Atlstride4 Atlbound5 Atlstride5 set_addr_remap_index_A "
    "Bslstride0 Bslstride1 Btlbound0 Btlstride0 Btlbound1 Btlstride1 Btlbound2 Btlstride2 set_addr_remap_index_B "
    "D8slstride0 D8slstride1 D8tlbound0 D8tlstride0 D8tlbound1 D8tlstride1 D8tlbound2 D8tlstride2 "
    "set_addr_remap_index_D8 "
    "Cslstride0 Cslstride1 Ctlbound0 Ctlstride0 Ctlbound1 Ctlstride1 Ctlbound2 Ctlstride2 set_addr_remap_index_C "
    "D32slstride0 D32slstride1 D32tlbound0 D32tlstride0 D32tlbound1 D32tlstride1 D32tlbound2 D32tlstride2 "
    "set_addr_remap_index_D32 "
    "delta_local_a delta_local_b delta_local_d8 delta_local_c delta_local_d32 "
    "bypassSIMD transposed_A transposed_B channel_en_C broadcast_C K N M").split()
CONV_PARAM_BYTES = 4 * (len(STREAMER_FIELDS) + 5 + 8)       # sizeof(nn_conv_t), all 32-bit fields


def conv_params(c):
    """nn_conv_t (nn/sw/nn_types.h) as bytes.  It is appended to the conv's weight blob, so core 0
    programs the CSRs from TCDM instead of ~80 slow loads from the memory island."""
    u8 = lambda x: int(x) & 0xFF
    sh = c["shift"]
    words = [int(c[f]) for f in STREAMER_FIELDS] + [
        (u8(c["subtraction_b"]) << 8) | u8(c["subtraction_a"]),
        (u8(c["min_int_i"]) << 24) | (u8(c["max_int_i"]) << 16) | (u8(c["output_zp_i"]) << 8) | u8(c["input_zp_i"]),
        c["double_round_i"],
        sh[0] | sh[1] << 8 | sh[2] << 16 | sh[3] << 24,
        sh[4] | sh[5] << 8 | sh[6] << 16 | sh[7] << 24] + [int(m) for m in c["multiplier"]]
    return np.array(words, dtype=np.int64).astype(np.uint32).tobytes()


def gemmx_cfg(name, v, tin, tout, wsize, blob):
    """Streamer + GeMMX CSR values of one conv (names as in snax-gemmx-lib.c)."""
    _, _, k, s, _, _, _ = CONV_CFG[name][1:]
    Ho = tout.H
    Wo = Ho
    lo = max((Ho - 1) * s + k - tin.H, 0) // 2     # Keras 'same': top/left padding
    o = 1 - lo                                     # window origin: padded row o, column X0-1+o
    K, N, M = k * k * tin.C8, tout.C8, Ho * Wo // 8
    Wq, Hp = tin.Wq, tin.Hp
    c = dict(
        # A: implicit im2col
        Aslstride0=1, Aslstride1=8 * s,
        Atlbound0=k, Atlstride0=8,
        Atlbound1=k, Atlstride1=8 * Wq,
        Atlbound2=tin.C8, Atlstride2=8 * Wq * Hp,
        Atlbound3=N, Atlstride3=0,
        Atlbound4=Wo // 8, Atlstride4=64 * s,
        Atlbound5=Ho, Atlstride5=8 * Wq * s,
        set_addr_remap_index_A=0,
        # B: weights
        Bslstride0=1, Bslstride1=8,
        Btlbound0=K, Btlstride0=64,
        Btlbound1=N, Btlstride1=64 * K,
        Btlbound2=M, Btlstride2=0,
        set_addr_remap_index_B=0,
        # D8: interior of the padded output
        D8slstride0=1, D8slstride1=8,
        D8tlbound0=N, D8tlstride0=tout.plane,
        D8tlbound1=Wo // 8, D8tlstride1=64,
        D8tlbound2=Ho, D8tlstride2=8 * tout.Wq,
        set_addr_remap_index_D8=0,
        # C: bias tile per N, broadcast over rows and M
        Cslstride0=8, Cslstride1=64,
        Ctlbound0=N, Ctlstride0=256,
        Ctlbound1=Wo // 8, Ctlstride1=0,
        Ctlbound2=Ho, Ctlstride2=0,
        set_addr_remap_index_C=0,
        # D32 unused (bypassSIMD = 0 zeroes its bounds)
        D32slstride0=8, D32slstride1=64,
        D32tlbound0=N, D32tlstride0=256,
        D32tlbound1=Wo // 8, D32tlstride1=0,
        D32tlbound2=Ho, D32tlstride2=0,
        set_addr_remap_index_D32=0,
        delta_local_a=tin.addr + tin.offset(0, o, tin.X0 - 1 + o),
        delta_local_b=blob.addr,
        delta_local_d8=tout.addr + tout.origin,
        delta_local_c=blob.addr + wsize,
        delta_local_d32=tout.addr + tout.origin,
        bypassSIMD=0, transposed_A=0, transposed_B=0, channel_en_C=0xFF, broadcast_C=1,
        # GeMMX
        K=K, N=N, M=M,
        subtraction_a=v["zp_in"], subtraction_b=0,
        input_zp_i=0, output_zp_i=v["zp_out"], max_int_i=v["hi"], min_int_i=v["lo"], double_round_i=0,
        shift=[int(v["shift"][l]) for l in range(8)],
        multiplier=[int(v["mult"][l]) for l in range(8)],
    )
    assert Wo % 8 == 0
    assert c["delta_local_d8"] % 64 == 0 and c["D8tlstride0"] % 64 == 0 and c["D8tlstride2"] % 64 == 0
    assert c["Atlbound0"] * c["Atlbound1"] * c["Atlbound2"] * c["Atlbound3"] * c["Atlbound4"] * c["Atlbound5"] == M * N * K
    return c


def allocate(bufs, limit):
    """First-fit (largest first) placement of buffers with overlapping lifetimes."""
    placed = []
    for b in sorted(bufs, key=lambda b: -b.size):
        off = 0
        for p in sorted((p for p in placed if p.live[0] <= b.live[1] and b.live[0] <= p.live[1]),
                        key=lambda p: p.addr):
            if off + b.size <= p.addr:
                break
            off = max(off, -(-(p.addr + p.size) // ALIGN) * ALIGN)
        b.addr = off
        assert off + b.size <= limit, f"TCDM overflow placing {b.name}"
        placed.append(b)
    return max(b.addr + b.size for b in placed)


class Program:
    """The compiled network: tensors, memory-island blobs, steps, TCDM plan."""

    def __init__(self, q):
        self.q = q
        act = q["act"]
        self.tensors = {n: Tensor(n, C, H, act[n][1]) for n, (C, H) in SHAPES.items()}
        for n, src in CONV_IN.items():
            if CONV_CFG[n][3] == 3:
                self.tensors[src].border = True
        self.steps, self.blobs = [], []
        for i, n in enumerate(ORDER):
            if n == "input":
                st = Step(i, "input", n, [], n)
            elif n.startswith("conv"):
                blob, wsize = conv_blob(n, q["conv"][n])
                blob.name = "w_" + n
                st = Step(i, "conv", n, [CONV_IN[n]], n, blob, dict(wsize=wsize))
            elif n.startswith("add"):
                cfg = dict(q["add"][n])
                st = Step(i, "add", n, list(ADDS[n]), n, add_lut(n, cfg), cfg)
            else:
                fc = q["fc"]
                data = pad64(fc["W"].astype(np.int8).tobytes()) + pad64(fc["bias"].astype(np.int32).tobytes())
                st = Step(i, "poolfc", n, ["add3"], None, Blob("w_fc", data),
                          dict(zp_in=fc["zp_in"], bias_off=len(pad64(fc["W"].astype(np.int8).tobytes()))))
            self.steps.append(st)
        # liveness
        prev = 0
        for st in self.steps:
            if st.out:
                t = self.tensors[st.out]
                t.live[0] = min(t.live[0], st.idx)
                t.live[1] = max(t.live[1], st.idx)
            for n in st.ins:
                self.tensors[n].live[1] = max(self.tensors[n].live[1], st.idx)
            if st.blob:
                st.blob.issue, st.blob.live = prev, [prev, st.idx]
                prev = st.idx
                self.blobs.append(st.blob)
        self.arena = TCDM_SIZE - TCDM_RESERVED
        self.peak = allocate(list(self.tensors.values()) + self.blobs, self.arena)
        for st in self.steps:
            if st.kind == "conv":
                st.cfg.update(gemmx_cfg(st.name, self.q["conv"][st.name], self.tensors[st.ins[0]],
                                        self.tensors[st.out], st.cfg["wsize"], st.blob))
                po = st.cfg["wsize"] + 256 * st.cfg["N"]
                pb = conv_params(st.cfg)
                st.blob.data = st.blob.data[:po] + pb + st.blob.data[po + len(pb):]

    def input_image(self, x_q):
        """Integer-reference input (3x32x32, values pixel-128) -> padded TCDM image bytes."""
        t = self.tensors["input"]
        return t.pack(np.asarray(x_q))

    def macs(self):
        """(useful MACs, GeMMX fires) per image."""
        useful = fires = 0
        for st in self.steps:
            if st.kind == "conv":
                W = self.q["conv"][st.name]["W"]
                Ho = self.tensors[st.out].H
                useful += W.size * Ho * Ho
                c = st.cfg
                fires += c["M"] * c["N"] * c["K"]
        return useful, fires
