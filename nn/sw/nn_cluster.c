// ResNet-8 runtime on the KUL cluster (SNAX GeMMX) inside chimera.
//
// Core 0 (GeMMX control, hart KUL_HART0) runs the compiled step table (build/gen/nn_net.c):
//   conv   -> one GeMMX call (streamer implicit im2col + SIMD requant/ReLU)
//   add    -> residual add + requant, rows split with core 1
//   poolfc -> global average pool (channel sums) + FC -> int32 logits
// Core 1 (DMA core, hart KUL_HART0 + 1, woken by core 0 through its CLINT msip) serves a job
// queue in TCDM: Snitch iDMA copies memory island -> TCDM (weights one conv ahead, input
// images) and its half of every residual add.
// After every step core 0 checksums the output tensor (outside the timed region) and
// compares it with the integer reference; logits are compared exactly.
#include <stdint.h>
#include "kul_chimera.h"
#include "snax-gemmx-params.h"
#include "snax-gemmx-lib.h"
#include "nn_net.h"
#include "nn_result.h"

#ifndef KUL_HART0
#define KUL_HART0 7          // mhartid of core 0 of chimera cluster 3 (1 + 2 + 2 + 2)
#endif
#define TCDM(off) ((uintptr_t)KUL_TCDM_BASE + (uintptr_t)(off))
#define CLINT_MSIP 0x02040000u
#define ADD_SHIFT 16
#define NN_X0 8              // interior column of a padded tensor (lower.Tensor.X0)

volatile nn_result_t nn_result;

// ---------------------------------------------------------------- core 0 <-> core 1 mailbox
enum { JOB_DMA = 1, JOB_ADD = 2, JOB_QUIT = 3 };
typedef struct { uint32_t kind, a0, a1, a2; } job_t;
#define QLEN 16
typedef struct {
    job_t q[QLEN];
    uint32_t head;                                // written by core 0
    uint32_t done;                                // written by core 1
} mailbox_t;
// top of TCDM (NN_TCDM_ARENA .. +256); the stacks are above it (nn_entry.S)
#define MB ((volatile mailbox_t *)TCDM(NN_TCDM_ARENA))

#ifdef NN_NATIVE
#include "native/native.h"   // host build: x86 stand-ins, core 1 jobs run inline (nn/sw/native)
#else
static inline uint32_t rdcycle(void) { uint32_t c; asm volatile("csrr %0, mcycle" : "=r"(c)); return c; }
static inline void fence(void) { asm volatile("fence" ::: "memory"); }
#define NATIVE_SERVE_JOBS()
#endif

static uint32_t core1_serve(void);
static uint32_t post(uint32_t kind, uint32_t a0, uint32_t a1, uint32_t a2) {
    volatile mailbox_t *mb = MB;
    uint32_t id = mb->head;
    while (id - mb->done >= QLEN) {}
    volatile job_t *j = &mb->q[id % QLEN];
    j->kind = kind; j->a0 = a0; j->a1 = a1; j->a2 = a2;
    fence();
    mb->head = id + 1;
    NATIVE_SERVE_JOBS();
    return id;
}
static void wait_job(uint32_t id) { while ((int32_t)(MB->done - id) <= 0) {} }

// ---------------------------------------------------------------- Snitch iDMA (core 1 only)
// dmsrc / dmdst / dmcpyi / dmstati as in snRuntime dma.h (64-bit addresses, high word 0).
static void dma_copy(uint32_t dst, uint32_t src, uint32_t size) {
#ifdef NN_NO_DMA
    for (uint32_t i = 0; i < size; i += 4)
        *(volatile uint32_t *)(dst + i) = *(const volatile uint32_t *)(src + i);
#else
    register uint32_t r_dl asm("a0") = dst;
    register uint32_t r_dh asm("a1") = 0;
    register uint32_t r_sl asm("a2") = src;
    register uint32_t r_sh asm("a3") = 0;
    register uint32_t r_sz asm("a4") = size;
    asm volatile(".word (0b0000000 << 25) | ((13) << 20) | ((12) << 15) | (0b000 << 12) | (0b0101011 << 0)"
                 :: "r"(r_sh), "r"(r_sl));                                       // dmsrc a2, a3
    asm volatile(".word (0b0000001 << 25) | ((11) << 20) | ((10) << 15) | (0b000 << 12) | (0b0101011 << 0)"
                 :: "r"(r_dh), "r"(r_dl));                                       // dmdst a0, a1
    asm volatile(".word (0b0000010 << 25) | (0b00000 << 20) | ((14) << 15) | (0b000 << 12) | ((10) << 7) | (0b0101011 << 0)"
                 : "+r"(r_dl) : "r"(r_sz));                                      // dmcpyi a0, a4, 0
    asm volatile("1: .word (0b0000100 << 25) | (0b00010 << 20) | (0b000 << 12) | ((5) << 7) | (0b0101011 << 0)\n"
                 "   bne t0, zero, 1b" ::: "t0");                                // dmstati t0, busy
#endif
}

// ---------------------------------------------------------------- core kernels
// rows [r0, r1) of the (C8 x H) interior rows; a row is H pixels x 8 channels = 8H bytes.
// Same arithmetic as nn.quant.hw.core_add_requant with the constants folded (nn_add_t):
//   out = lut[((a*ma + b*mb + kc) >> 16) - tmin]
// Byte loads/stores (lb sign-extends for free), one pixel (8 channels) per iteration and a
// table clamp (no branches): ~10 instructions per element.
static void add_rows(const nn_add_t *p, uint32_t r0, uint32_t r1) {
    const int32_t ma = p->ma, mb = p->mb, kc = p->kc;
    const int8_t *restrict lut = (const int8_t *)TCDM(p->lut) - p->tmin;
    const uint32_t n = p->H * 8, rs = p->Wq * 8, Hp = p->H + 2;
    for (uint32_t r = r0; r < r1; r++) {
        uint32_t off = ((r / p->H) * Hp + (r % p->H)) * rs;      // C8 group plane + row
        const int8_t *restrict a = (const int8_t *)TCDM(p->a + off);   // restrict: lets clang
        const int8_t *restrict b = (const int8_t *)TCDM(p->b + off);   // interleave the 8 lanes
        int8_t *restrict o = (int8_t *)TCDM(p->out + off);
        for (const int8_t *end = a + n; a != end; a += 8, b += 8, o += 8) {
            int32_t t[8];                  // three passes: independent ops back to back hide the
#pragma clang loop unroll(full)            // load and multiply latencies of the in-order core
            for (uint32_t j = 0; j < 8; j++) t[j] = a[j] * ma;
#pragma clang loop unroll(full)
            for (uint32_t j = 0; j < 8; j++) t[j] += b[j] * mb + kc;
#pragma clang loop unroll(full)
            for (uint32_t j = 0; j < 8; j++) o[j] = lut[t[j] >> ADD_SHIFT];
        }
    }
}

static void pool_fc(const nn_poolfc_t *p, int32_t *logits) {
    int32_t pool[64];
    const uint32_t rs = p->Wq * 8, Hp = p->H + 2;
    for (uint32_t g = 0; g < p->C8; g++) {
        int32_t s[8] = {0};
        for (uint32_t h = 0; h < p->H; h++) {
            const int8_t *x = (const int8_t *)TCDM(p->in + (g * Hp + h) * rs);
            for (uint32_t w = 0; w < p->H; w++, x += 8)
                for (uint32_t j = 0; j < 8; j++) s[j] += x[j];
        }
        for (uint32_t j = 0; j < 8; j++) pool[g * 8 + j] = s[j] - (int32_t)(p->H * p->H) * p->zp;
    }
    const int8_t *W = (const int8_t *)TCDM(p->w);
    const int32_t *bias = (const int32_t *)TCDM(p->bias);
    for (uint32_t k = 0; k < p->n_out; k++) {
        int32_t acc = bias[k];
        for (uint32_t c = 0; c < p->n_in; c++) acc += (int32_t)W[k * p->n_in + c] * pool[c];
        logits[k] = acc;
    }
}

// Zero-point border of a padded tensor: top and bottom rows, columns 0 (right border of the row
// above) and NN_X0-1 (left border) of every interior row, and the 64 B tail after the last plane.
static void fill_border(const nn_step_t *s) {
    const uint32_t Wq = s->out_Wq, Hp = s->out_H + 2, rs = Wq * 8, plane = Hp * rs;
    const uint32_t v = (uint8_t)s->border_zp * 0x01010101u;
    uint32_t base = s->out - (Wq + NN_X0) * 8;            // s->out = interior pixel (0,0) of group 0
    for (uint32_t g = 0; g < s->out_C8; g++, base += plane) {
        volatile uint32_t *top = (volatile uint32_t *)TCDM(base);
        volatile uint32_t *bot = (volatile uint32_t *)TCDM(base + (Hp - 1) * rs);
        for (uint32_t i = 0; i < Wq * 2; i++) { top[i] = v; bot[i] = v; }
        for (uint32_t r = 1; r < Hp - 1; r++) {
            volatile uint32_t *l = (volatile uint32_t *)TCDM(base + r * rs);
            l[0] = v; l[1] = v; l[2 * NN_X0 - 2] = v; l[2 * NN_X0 - 1] = v;
        }
    }
    volatile uint32_t *tail = (volatile uint32_t *)TCDM(base);
    for (uint32_t i = 0; i < 16; i++) tail[i] = v;
}

static void checksum(const nn_step_t *s, uint32_t *c1, uint32_t *c2) {
    uint32_t s1 = 0, s2 = 0;
    const uint32_t rs = s->out_Wq * 8, Hp = s->out_H + 2, words = s->out_H * 2;
    for (uint32_t g = 0; g < s->out_C8; g++)
        for (uint32_t h = 0; h < s->out_H; h++) {
            const volatile uint32_t *p = (const volatile uint32_t *)TCDM(s->out + (g * Hp + h) * rs);
            for (uint32_t i = 0; i < words; i++) { s1 += p[i]; s2 += s1; }
        }
    *c1 = s1; *c2 = s2;
}

_Static_assert(sizeof(nn_conv_t) == NN_CONV_PARAM_BYTES, "nn_conv_t layout != lower.conv_params");
static void gemmx_conv(const nn_conv_t *c) {
    set_gemmx_streamer_csr(
        c->Aslstride0, c->Aslstride1, c->Atlbound0, c->Atlstride0, c->Atlbound1, c->Atlstride1,
        c->Atlbound2, c->Atlstride2, c->Atlbound3, c->Atlstride3, c->Atlbound4, c->Atlstride4,
        c->Atlbound5, c->Atlstride5, c->set_addr_remap_index_A,
        c->Bslstride0, c->Bslstride1, c->Btlbound0, c->Btlstride0, c->Btlbound1, c->Btlstride1,
        c->Btlbound2, c->Btlstride2, c->set_addr_remap_index_B,
        c->D8slstride0, c->D8slstride1, c->D8tlbound0, c->D8tlstride0, c->D8tlbound1,
        c->D8tlstride1, c->D8tlbound2, c->D8tlstride2, c->set_addr_remap_index_D8,
        c->Cslstride0, c->Cslstride1, c->Ctlbound0, c->Ctlstride0, c->Ctlbound1, c->Ctlstride1,
        c->Ctlbound2, c->Ctlstride2, c->set_addr_remap_index_C,
        c->D32slstride0, c->D32slstride1, c->D32tlbound0, c->D32tlstride0, c->D32tlbound1,
        c->D32tlstride1, c->D32tlbound2, c->D32tlstride2, c->set_addr_remap_index_D32,
        c->delta_local_a, c->delta_local_b, c->delta_local_d8, c->delta_local_c,
        c->delta_local_d32, c->bypassSIMD, c->transposed_A, c->transposed_B, c->channel_en_C,
        c->broadcast_C);
    set_gemmx_csr(c->K, c->N, c->M, c->subtractions, c->csr0, c->csr1, c->shift0, c->shift1,
                  c->mult[0], c->mult[1], c->mult[2], c->mult[3], c->mult[4], c->mult[5],
                  c->mult[6], c->mult[7], c->M * c->N, c->bypassSIMD);
    set_gemmx_streamer_start();
    set_gemmx_start();
    wait_gemmx_and_streamer();
}

// ---------------------------------------------------------------- core 0
static void mismatch(uint32_t img, uint32_t step, uint32_t *err) {
    if (nn_result.first_bad == 0xFFFFFFFFu) nn_result.first_bad = (img << 8) | step;
    (*err)++;
}

static uint32_t run_image(uint32_t img) {
    uint32_t err = 0, blob_job[NN_N_BLOBS];
    uint32_t t_img = 0;
    for (uint32_t i = 0; i < NN_N_STEPS; i++) {
        const nn_step_t *s = &nn_steps[i];
        uint32_t t0 = rdcycle();
        for (uint32_t b = 0; b < NN_N_BLOBS; b++)            // prefetch (one conv ahead)
            if (nn_blobs[b].issue == i)
                blob_job[b] = post(JOB_DMA, TCDM(nn_blobs[b].dst), (uint32_t)nn_blobs[b].src, nn_blobs[b].size);
        if (s->border_zp != 999) fill_border(s);
        if (s->blob >= 0) wait_job(blob_job[s->blob]);
        switch (s->kind) {
        case NN_INPUT:
            wait_job(post(JOB_DMA, TCDM(NN_INPUT_ADDR), (uint32_t)nn_images[img], NN_INPUT_SIZE));
            break;
        case NN_CONV:
            gemmx_conv((const nn_conv_t *)TCDM((uintptr_t)s->p));   // params arrive with the weights
            if (img == 0) {
                nn_result.gemmx_perf[i] = read_gemmx_perf_counter();
                nn_result.streamer_perf[i] = read_gemmx_streamer_perf_counter();
            }
            break;
        case NN_ADD: {
            const nn_add_t *p = (const nn_add_t *)s->p;
            uint32_t rows = p->C8 * p->H, half = rows / 2;
            uint32_t id = post(JOB_ADD, (uint32_t)p, half, rows);   // core 1: second half
            add_rows(p, 0, half);
            wait_job(id);
            break;
        }
        case NN_POOLFC: {
            int32_t lg[NN_N_CLASSES];
            pool_fc((const nn_poolfc_t *)s->p, lg);
            uint32_t best = 0;
            for (uint32_t k = 0; k < NN_N_CLASSES; k++) {
                nn_result.logits[img][k] = lg[k];
                if (lg[k] != nn_expect_logits[img][k]) mismatch(img, i, &err);
                if (lg[k] > lg[best]) best = k;
            }
            nn_result.pred[img] = best;
            break;
        }
        }
        uint32_t dt = rdcycle() - t0;
        nn_result.cycles[img][i] = dt;
        t_img += dt;
#ifdef NN_STOP_AFTER
        if (i == NN_STOP_AFTER) {                    // debug: freeze for a TCDM dump (run_nn.tcl)
            nn_result.marker = 0xDEAD0000u | i;
            for (;;) {}
        }
#endif
        if (s->out_C8) {                                         // check (not timed)
            uint32_t c1, c2;
            checksum(s, &c1, &c2);
            if (c1 != nn_expect_chk[img][i][0] || c2 != nn_expect_chk[img][i][1]) mismatch(img, i, &err);
#ifdef NN_FULL_CHECK
            if (img == 0) {
                const int8_t *e = nn_expect_full[i];
                const uint32_t rs = s->out_Wq * 8, Hp = s->out_H + 2, n = s->out_H * 8;
                for (uint32_t g = 0; g < s->out_C8; g++)
                    for (uint32_t h = 0; h < s->out_H; h++, e += n) {
                        const int8_t *o = (const int8_t *)TCDM(s->out + (g * Hp + h) * rs);
                        for (uint32_t k = 0; k < n; k++)
                            if (o[k] != e[k]) {
                                if (nn_result.full_err[i]++ == 0 && nn_result.full_first[0] == 0) {
                                    nn_result.full_first[0] = (i << 24) | (uint32_t)(e - nn_expect_full[i] + k);
                                    nn_result.full_first[1] = (uint8_t)o[k];
                                    nn_result.full_first[2] = (uint8_t)e[k];
                                }
                                mismatch(img, i, &err);
                            }
                    }
            }
#endif
        }
    }
    nn_result.total[img] = t_img;
    return err;
}

static int32_t core0_main(uint32_t hart) {
    volatile mailbox_t *mb = MB;
    mb->head = 0;
    mb->done = 0;
    nn_result.errors = 0;
    nn_result.first_bad = 0xFFFFFFFFu;
    fence();
    *(volatile uint32_t *)(CLINT_MSIP + 4 * (hart + 1)) = 1;     // wake core 1
    uint32_t err = 0;
    for (uint32_t img = 0; img < NN_N_IMAGES; img++) {
        err += run_image(img);
        nn_result.errors = err;
    }
    wait_job(post(JOB_QUIT, 0, 0, 0));
    nn_result.marker = 0xC0FFEE00u;
    return (int32_t)((err != 0) << 1);                           // bootrom ORs in bit 0
}

// ---------------------------------------------------------------- core 1
static uint32_t core1_serve(void) {               // execute the next job, return its kind
    volatile mailbox_t *mb = MB;
    uint32_t id = mb->done;
    while (mb->head == id) {}
    fence();
    volatile job_t *j = &mb->q[id % QLEN];
    uint32_t kind = j->kind;
    if (kind == JOB_DMA) dma_copy(j->a0, j->a1, j->a2);
    else if (kind == JOB_ADD) add_rows((const nn_add_t *)j->a0, j->a1, j->a2);
    fence();
    mb->done = id + 1;
    return kind;
}

static int32_t core1_main(void) {
    while (core1_serve() != JOB_QUIT) {}
    return 0;
}

int32_t nn_cluster_main(uint32_t hart) {
    return hart == KUL_HART0 ? core0_main(hart) : core1_main();
}
