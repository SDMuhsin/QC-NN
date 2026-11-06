// Host-side run of the complete cluster program (nn_cluster.c + build/gen/nn_net.c) as a static
// 32-bit x86 binary without libc.  The GeMMX library calls are replaced by a C model of the
// streamer AGUs + GeMM array + RescaleSIMD driven by the same CSR values; the result block is
// printed and the exit code is 0 iff every checksum and logit matched.
//   nn/sw/native/run.sh
#include <stdint.h>
#include "kul_chimera.h"
#include "nn_result.h"

// ---------------------------------------------------------------- syscalls (int 0x80)
static long sys(long n, long a, long b, long c, long d, long e, long f) {
    long r;
    __asm__ volatile("push %%ebp; mov %7, %%ebp; int $0x80; pop %%ebp"
                     : "=a"(r) : "a"(n), "b"(a), "c"(b), "d"(c), "S"(d), "D"(e), "m"(f) : "memory");
    return r;
}
static void put(const char *s) { long n = 0; while (s[n]) n++; sys(4, 1, (long)s, n, 0, 0, 0); }
static void putd(int32_t v) {
    char b[16]; int i = 15; uint32_t u = v < 0 ? -(uint32_t)v : (uint32_t)v;
    b[i] = 0;
    do { b[--i] = '0' + u % 10; u /= 10; } while (u);
    if (v < 0) b[--i] = '-';
    put(b + i);
}
void *memset(void *d, int c, uint32_t n) { uint8_t *p = d; while (n--) *p++ = (uint8_t)c; return d; }
void *memcpy(void *d, const void *s, uint32_t n) { uint8_t *p = d; const uint8_t *q = s; while (n--) *p++ = *q++; return d; }

// ---------------------------------------------------------------- GeMMX model (snax-gemmx-lib API)
static struct {
    int32_t a[15], b[9], d8[9], c[9], d32[9];
    int32_t base_a, base_b, base_d8, base_c;
    int32_t K, N, M, sub, csr0, csr1, sh0, sh1, mult[8];
} g;

void set_gemmx_streamer_csr(
    int Aslstride0, int Aslstride1, int Atlbound0, int Atlstride0, int Atlbound1, int Atlstride1,
    int Atlbound2, int Atlstride2, int Atlbound3, int Atlstride3, int Atlbound4, int Atlstride4,
    int Atlbound5, int Atlstride5, int set_addr_remap_index_A, int Bslstride0, int Bslstride1,
    int Btlbound0, int Btlstride0, int Btlbound1, int Btlstride1, int Btlbound2, int Btlstride2,
    int set_addr_remap_index_B, int D8slstride0, int D8slstride1, int D8tlbound0, int D8tlstride0,
    int D8tlbound1, int D8tlstride1, int D8tlbound2, int D8tlstride2, int set_addr_remap_index_D8,
    int Cslstride0, int Cslstride1, int Ctlbound0, int Ctlstride0, int Ctlbound1, int Ctlstride1,
    int Ctlbound2, int Ctlstride2, int set_addr_remap_index_C, int D32slstride0, int D32slstride1,
    int D32tlbound0, int D32tlstride0, int D32tlbound1, int D32tlstride1, int D32tlbound2,
    int D32tlstride2, int set_addr_remap_index_D32, int delta_local_a, int delta_local_b,
    int delta_local_d8, int delta_local_c, int delta_local_d32, int bypassSIMD, int32_t transpose_A,
    int32_t transpose_B, int32_t channel_en_C, int32_t broadcast_C) {
    int32_t a[15] = {Aslstride0, Aslstride1, Atlbound0, Atlstride0, Atlbound1, Atlstride1, Atlbound2,
                     Atlstride2, Atlbound3, Atlstride3, Atlbound4, Atlstride4, Atlbound5, Atlstride5,
                     set_addr_remap_index_A};
    int32_t b[9] = {Bslstride0, Bslstride1, Btlbound0, Btlstride0, Btlbound1, Btlstride1, Btlbound2,
                    Btlstride2, set_addr_remap_index_B};
    int32_t d8[9] = {D8slstride0, D8slstride1, D8tlbound0, D8tlstride0, D8tlbound1, D8tlstride1,
                     D8tlbound2, D8tlstride2, set_addr_remap_index_D8};
    int32_t c[9] = {Cslstride0, Cslstride1, Ctlbound0, Ctlstride0, Ctlbound1, Ctlstride1, Ctlbound2,
                    Ctlstride2, set_addr_remap_index_C};
    memcpy(g.a, a, sizeof a); memcpy(g.b, b, sizeof b); memcpy(g.d8, d8, sizeof d8); memcpy(g.c, c, sizeof c);
    g.base_a = KUL_TCDM_BASE + delta_local_a; g.base_b = KUL_TCDM_BASE + delta_local_b;
    g.base_d8 = KUL_TCDM_BASE + delta_local_d8; g.base_c = KUL_TCDM_BASE + delta_local_c;
    (void)D32slstride0; (void)D32slstride1; (void)D32tlbound0; (void)D32tlstride0; (void)D32tlbound1;
    (void)D32tlstride1; (void)D32tlbound2; (void)D32tlstride2; (void)set_addr_remap_index_D32;
    (void)delta_local_d32; (void)bypassSIMD; (void)transpose_A; (void)transpose_B; (void)channel_en_C;
    (void)broadcast_C;
}

void set_gemmx_csr(int K, int N, int M, int sub, uint32_t csr0, uint32_t csr1, int sh0, int sh1,
                   int m0, int m1, int m2, int m3, int m4, int m5, int m6, int m7, uint32_t tlb, uint32_t byp) {
    g.K = K; g.N = N; g.M = M; g.sub = sub; g.csr0 = csr0; g.csr1 = csr1; g.sh0 = sh0; g.sh1 = sh1;
    int32_t m[8] = {m0, m1, m2, m3, m4, m5, m6, m7};
    memcpy(g.mult, m, sizeof m);
    (void)tlb; (void)byp;
}
void set_gemmx_streamer_start(void) {}
void set_gemmx_start(void) {}
uint32_t read_gemmx_perf_counter(void) { return 0; }
uint32_t read_gemmx_streamer_perf_counter(void) { return 0; }

// address of temporal iteration t (innermost bound first) of an AGU with n loops
static int32_t agu(int32_t base, const int32_t *bounds_strides, int n, uint32_t t) {
    int32_t a = base;
    for (int i = 0; i < n; i++) {
        uint32_t b = bounds_strides[2 * i];
        a += (int32_t)(t % b) * bounds_strides[2 * i + 1];
        t /= b;
    }
    return a;
}

static int32_t rescale(int32_t acc, int lane) {               // RescalePE, double_round = 0
    int8_t izp = g.csr0 & 0xff, ozp = (g.csr0 >> 8) & 0xff, mx = (g.csr0 >> 16) & 0xff, mn = g.csr0 >> 24;
    uint32_t sh = ((lane < 4 ? g.sh0 : g.sh1) >> (8 * (lane & 3))) & 0xff;
    int64_t v0 = (int64_t)((int64_t)acc - izp) * g.mult[lane];
    int32_t v1 = (int32_t)(uint32_t)(v0 >> (sh - 1));
    int32_t v2 = (v1 >> 1) + ozp;
    return v2 > mx ? mx : v2 < mn ? mn : v2;
}

void wait_gemmx_and_streamer(void) {
    const int8_t sa = g.sub & 0xff, sb = (g.sub >> 8) & 0xff;
    // A: 6 loops (bounds/strides at a[2..13]), B: 3 loops, C / D8: 3 loops
    for (uint32_t t = 0; t < (uint32_t)(g.M * g.N); t++) {
        int32_t acc[8][8];
        const int32_t *cb = (const int32_t *)agu(g.base_c, &g.c[2], 3, t);    // broadcast C
        for (int r = 0; r < 8; r++)
            for (int c = 0; c < 8; c++) acc[r][c] = cb[c];
        for (int k = 0; k < g.K; k++) {
            uint32_t i = t * g.K + k;
            int32_t aa = agu(g.base_a, &g.a[2], 6, i), ba = agu(g.base_b, &g.b[2], 3, i);
            for (int r = 0; r < 8; r++)
                for (int c = 0; c < 8; c++) {
                    const int8_t *pa = (const int8_t *)(aa + r * g.a[1]);
                    const int8_t *pb = (const int8_t *)(ba + c * g.b[1]);
                    int32_t s = 0;
                    for (int x = 0; x < 8; x++) s += (pa[x] - sa) * (pb[x] - sb);
                    acc[r][c] += s;
                }
        }
        int32_t da = agu(g.base_d8, &g.d8[2], 3, t);
        for (int r = 0; r < 8; r++)
            for (int c = 0; c < 8; c++) ((int8_t *)(da + r * g.d8[1]))[c] = (int8_t)rescale(acc[r][c], c);
    }
}

// ---------------------------------------------------------------- main
extern int32_t nn_cluster_main(uint32_t hart);

void _start(void) {
    long t = sys(192, KUL_TCDM_BASE, KUL_TCDM_SIZE, 3, 0x32, -1, 0);       // mmap2 TCDM, FIXED
    long c = sys(192, 0x02040000, 4096, 3, 0x32, -1, 0);                   // CLINT page
    if (t != KUL_TCDM_BASE || c != 0x02040000) { put("mmap failed\n"); sys(1, 2, 0, 0, 0, 0, 0); }
    for (uint32_t i = 0; i < KUL_TCDM_SIZE; i++)                            // TCDM starts as garbage
        ((volatile uint8_t *)KUL_TCDM_BASE)[i] = (uint8_t)(i * 2654435761u >> 13);
    int32_t ret = nn_cluster_main(KUL_HART0);
    put("native run: marker "); putd(nn_result.marker == 0xC0FFEE00u);
    put(" errors "); putd(nn_result.errors); put(" first_bad "); putd(nn_result.first_bad);
    put("\n");
    for (int i = 0; i < NN_N_IMAGES; i++) {
        put("  image "); putd(i); put(" pred "); putd(nn_result.pred[i]); put(" logits");
        for (int k = 0; k < NN_N_CLASSES; k++) { put(" "); putd(nn_result.logits[i][k]); }
        put("\n");
    }
    sys(1, (ret == 0 && nn_result.errors == 0 && nn_result.marker == 0xC0FFEE00u) ? 0 : 1, 0, 0, 0, 0, 0);
}
