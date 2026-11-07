// Host (x86 -m32) run of nn/sw on a C model of QC-GeMMX: nn/sw/native/native.c (syscalls, TCDM
// mmap, streamer CSR capture, RescaleSIMD, _start) with the array replaced by the QC datapath of
// qcacc/ARCH.md.  B reader: 1 channel x 64 b, one tile code word per fire at the B AGU address
// (Bslstride0/1 unused).  Built by qcacc/sw/native.sh qc (NN_NATIVE_C=this file).
#define wait_gemmx_and_streamer nn_dense_wait_and_streamer   // keep the dense model, unused here
#include "../../nn/sw/native/native.c"
#undef wait_gemmx_and_streamer

static int32_t trit(uint32_t c) {                             // 00 = 0, 01 = +1, 11 = -1
    if (c == 2) { put("illegal trit code 10\n"); sys(1, 3, 0, 0, 0, 0, 0); }
    return c == 0 ? 0 : c == 1 ? 1 : -1;
}

void wait_gemmx_and_streamer(void) {
    const int8_t sa = g.sub & 0xff;
    for (uint32_t t = 0; t < (uint32_t)(g.M * g.N); t++) {
        int32_t acc[8][8];
        const int32_t *cb = (const int32_t *)agu(g.base_c, &g.c[2], 3, t);    // broadcast C
        for (int r = 0; r < 8; r++)
            for (int c = 0; c < 8; c++) acc[r][c] = cb[c];
        for (int k = 0; k < g.K; k++) {
            uint32_t i = t * g.K + k;
            int32_t aa = agu(g.base_a, &g.a[2], 6, i);
            const uint32_t *pw = (const uint32_t *)agu(g.base_b, &g.b[2], 3, i);
            uint64_t w = (uint64_t)pw[0] | (uint64_t)pw[1] << 32;
            // column decoder: per column n and pair p, coefficients (ca, cb) on (x_2p, x_2p+1)
            int32_t ca[8][4], cbk[8][4];
            for (int j = 0; j < 4; j++)
                for (int p = 0; p < 4; p++) {
                    uint32_t nib = (uint32_t)(w >> (4 * (j * 4 + p))) & 15;
                    int32_t a = trit(nib & 3), b = trit(nib >> 2);
                    ca[2 * j][p] = a; cbk[2 * j][p] = b;
                    ca[2 * j + 1][p] = b; cbk[2 * j + 1][p] = a;
                }
            for (int r = 0; r < 8; r++) {
                const int8_t *pa = (const int8_t *)(aa + r * g.a[1]);
                int32_t x[8], s[4], d[4];
                for (int q = 0; q < 8; q++) x[q] = pa[q] - sa;            // 9 b
                for (int p = 0; p < 4; p++) { s[p] = x[2 * p] + x[2 * p + 1]; d[p] = x[2 * p] - x[2 * p + 1]; }
                for (int c = 0; c < 8; c++) {
                    int32_t sum = 0;
                    for (int p = 0; p < 4; p++) {
                        int32_t u = ca[c][p], v = cbk[c][p], sel;
                        if (u && v) sel = u == v ? u * s[p] : u * d[p];
                        else if (u) sel = u * x[2 * p];
                        else if (v) sel = v * x[2 * p + 1];
                        else sel = 0;
                        sum += sel;
                    }
                    acc[r][c] = (int32_t)((uint32_t)acc[r][c] + (uint32_t)sum);
                }
            }
        }
        int32_t da = agu(g.base_d8, &g.d8[2], 3, t);
        for (int r = 0; r < 8; r++)
            for (int c = 0; c < 8; c++) ((int8_t *)(da + r * g.d8[1]))[c] = (int8_t)rescale(acc[r][c], c);
    }
}
