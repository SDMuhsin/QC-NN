"""QC-GeMMX weight codec (ARCH.md "B: 64 b per 8x8 weight tile").

An 8x8 GeMMX weight tile T[n][k] (n = output channel in the group, k = input channel in the
Cin/8 group, one kernel tap) consists of 16 blocks (j = n/2, p = k/2), each [[a, b], [b, a]]:
    T[2j][2p] = a, T[2j][2p+1] = b, T[2j+1][2p] = b, T[2j+1][2p+1] = a,   a, b in {-1, 0, 1}.
Block code (4 b) at bits [4i+3:4i] of the tile word, i = j*4 + p: bits [1:0] = a, [3:2] = b,
trit 00 = 0, 01 = +1, 11 = -1 (10 is illegal).  Tile word = uint64, stored little endian.

Row signs: s2 stores rows with a negative BN scale as -M.  `row_signs` finds sigma[co] in {+1, -1}
per output row so that sigma * W is QC (sigma[2j] = +1, sigma[2j+1] = relative sign of the pair);
the compiler then stores M = sigma * W, negates the bias and the requant multiplier of flipped rows.
Don't-care columns (input channels padded by the hardware, conv0 cin 3 -> 8: they multiply
a - subtraction_a = 0) take any value that keeps the block QC.
"""
import numpy as np

TRIT_ENC = {0: 0b00, 1: 0b01, -1: 0b11}
TRIT_DEC = np.array([0, 1, 9, -1], dtype=np.int64)       # 9 marks the illegal code 10


def trit_decode(c):
    v = TRIT_DEC[np.asarray(c) & 3]
    if (v == 9).any():
        raise ValueError("illegal trit code 0b10")
    return v


def _pad(W):
    """W[cout, cin, k, k] -> (Wp[cout, ci8*8, k, k] int64, known[ci8*8] bool)."""
    W = np.asarray(W, dtype=np.int64)
    cout, cin, k, _ = W.shape
    c8 = -(-cin // 8) * 8
    Wp = np.zeros((cout, c8, k, k), dtype=np.int64)
    Wp[:, :cin] = W
    known = np.arange(c8) < cin
    return Wp, known


def row_signs(W):
    """Per-row sign sigma[cout] such that sigma * W (int, [cout, cin, k, k]) is QC (b = 2).
    Raises ValueError if a row pair has no consistent relative sign."""
    Wp, known = _pad(W)
    cout = Wp.shape[0]
    assert cout % 2 == 0
    full = known[0::2] & known[1::2]                           # blocks with both columns known
    sig = np.ones(cout, dtype=np.int64)
    for j in range(cout // 2):
        r0 = Wp[2 * j, 0::2][full]                             # [p_known, k, k]: col 2p
        r0b = Wp[2 * j, 1::2][full]                            # col 2p+1
        r1 = Wp[2 * j + 1, 0::2][full]
        r1b = Wp[2 * j + 1, 1::2][full]
        ok = [rel for rel in (1, -1) if np.array_equal(r0, rel * r1b) and np.array_equal(r0b, rel * r1)]
        if not ok:
            raise ValueError(f"rows {2 * j},{2 * j + 1}: no sign makes every 2x2 block [[a,b],[b,a]]")
        sig[2 * j + 1] = ok[0]
    return sig


def encode_tile(T, known=None):
    """T[8 n][8 k] int in {-1,0,1} (QC) -> uint64 code word.  known[8]: columns that must match
    exactly (default all).  Raises ValueError if not encodable."""
    T = np.asarray(T, dtype=np.int64)
    known = np.ones(8, bool) if known is None else np.asarray(known, bool)
    word = 0
    for j in range(4):
        for p in range(4):
            k0, k1 = known[2 * p], known[2 * p + 1]
            (w00, w01), (w10, w11) = T[2 * j:2 * j + 2, 2 * p:2 * p + 2]
            if k0 and k1:
                if w00 != w11 or w01 != w10:
                    raise ValueError(f"block (j={j}, p={p}) {[[w00, w01], [w10, w11]]} is not [[a,b],[b,a]]")
                a, b = w00, w01
            elif k0:
                a, b = w00, w10
            elif k1:
                a, b = w11, w01
            else:
                a, b = 0, 0
            if a not in TRIT_ENC or b not in TRIT_ENC:
                raise ValueError(f"block (j={j}, p={p}): weight not in {{-1,0,1}}: {a}, {b}")
            word |= (TRIT_ENC[int(a)] | TRIT_ENC[int(b)] << 2) << (4 * (j * 4 + p))
    return np.uint64(word)


def decode_tile(word):
    """uint64 code word -> T[8 n][8 k] int64 (raises on an illegal trit)."""
    word = int(word)
    nib = np.array([(word >> (4 * i)) & 15 for i in range(16)]).reshape(4, 4)     # [j, p]
    a, b = trit_decode(nib), trit_decode(nib >> 2)
    T = np.zeros((8, 8), dtype=np.int64)
    T[0::2, 0::2] = a
    T[0::2, 1::2] = b
    T[1::2, 0::2] = b
    T[1::2, 1::2] = a
    return T


def encode_conv(W):
    """int8 conv weights W[cout, cin, k, k] -> (codes uint64 [cout/8, ci8, k, k] in GeMMX B tile
    order, sigma[cout]).  decode_conv(codes)[:, :cin] == sigma[:, None, None, None] * W."""
    sig = row_signs(W)
    Wp, known = _pad(np.asarray(W, dtype=np.int64) * sig[:, None, None, None])
    cout, c8, k, _ = Wp.shape
    codes = np.zeros((cout // 8, c8 // 8, k, k), dtype=np.uint64)
    for g in range(cout // 8):
        for c in range(c8 // 8):
            for y in range(k):
                for x in range(k):
                    codes[g, c, y, x] = encode_tile(Wp[8 * g:8 * g + 8, 8 * c:8 * c + 8, y, x],
                                                    known[8 * c:8 * c + 8])
    return codes, sig


def decode_conv(codes):
    """codes [co8, ci8, k, k] -> M[co8*8, ci8*8, k, k] int64."""
    G, C, k, _ = codes.shape
    M = np.zeros((G * 8, C * 8, k, k), dtype=np.int64)
    for g in range(G):
        for c in range(C):
            for y in range(k):
                for x in range(k):
                    M[8 * g:8 * g + 8, 8 * c:8 * c + 8, y, x] = decode_tile(codes[g, c, y, x])
    return M
