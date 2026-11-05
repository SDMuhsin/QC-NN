// GeMM offloaded to the SNAX GeMMX accelerator of the KUL cluster inside chimera.
// Same computation and golden data as snax_cluster's sw/apps/snax-gemmx-matmul
// (data.h from its datagen, params.hjson: M=1 K=18 N=2 -> (8x144 int8) x (144x16 int8) + C,
// rescaled by the SIMD unit to int8), but data movement is done by core 0 itself
// (memory island <-> TCDM through the cluster's narrow AXI port) instead of the DMA core.
#include <stdint.h>
#include "kul_chimera.h"
#include "data.h"
#include "snax-gemmx-params.h"
#include "snax-gemmx-lib.h"

volatile uint32_t kul_result[8];   // in the memory island, read by the host

static void copy_bytes(volatile int8_t *dst, const int8_t *src, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) dst[i] = src[i];
}
static void copy_words(volatile int32_t *dst, const int32_t *src, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) dst[i] = src[i];
}
static inline uint32_t rdcycle(void) { uint32_t c; asm volatile("csrr %0, mcycle" : "=r"(c)); return c; }

int32_t kul_gemm(void) {
    int8_t  *local_a   = (int8_t  *)(snrt_l1_next() + delta_local_a);
    int8_t  *local_b   = (int8_t  *)(snrt_l1_next() + delta_local_b);
    int32_t *local_c   = (int32_t *)(snrt_l1_next() + delta_local_c);
    int8_t  *local_d8  = (int8_t  *)(snrt_l1_next() + delta_local_d8);
    int32_t *local_d32 = (int32_t *)(snrt_l1_next() + delta_local_d32);

    uint32_t t0 = rdcycle();
    copy_bytes(local_a, A, M * K * meshRow * tileSize);
    copy_bytes(local_b, B, N * K * tileSize * meshCol);
    copy_words(local_c, C, M * N * meshRow * meshCol);
    uint32_t t1 = rdcycle();

    set_gemmx_streamer_csr(
        Aslstride0, Aslstride1, Atlbound0, Atlstride0, Atlbound1, Atlstride1, Atlbound2,
        Atlstride2, Atlbound3, Atlstride3, Atlbound4, Atlstride4, Atlbound5, Atlstride5,
        set_addr_remap_index_A,
        Bslstride0, Bslstride1, Btlbound0, Btlstride0, Btlbound1, Btlstride1, Btlbound2,
        Btlstride2, set_addr_remap_index_B,
        D8slstride0, D8slstride1, D8tlbound0, D8tlstride0, D8tlbound1, D8tlstride1,
        D8tlbound2, D8tlstride2, set_addr_remap_index_D8,
        Cslstride0, Cslstride1, Ctlbound0, Ctlstride0, Ctlbound1, Ctlstride1, Ctlbound2,
        Ctlstride2, set_addr_remap_index_C,
        D32slstride0, D32slstride1, D32tlbound0, D32tlstride0, D32tlbound1, D32tlstride1,
        D32tlbound2, D32tlstride2, set_addr_remap_index_D32,
        delta_local_a, delta_local_b, delta_local_d8, delta_local_c, delta_local_d32,
        bypassSIMD, transposed_A, transposed_B, channel_en_C, broadcast_C);
    uint32_t subtraction_setting = gen_subtraction_config(subtraction_a, subtraction_b);
    uint32_t csr0 = gen_csr0_config(input_zp_i, output_zp_i, max_int_i, min_int_i);
    uint32_t csr1 = gen_csr1_config(double_round_i);
    set_gemmx_csr(K, N, M, subtraction_setting, csr0, csr1, shared_bitpacked_shift0,
                  shared_bitpacked_shift1, shared_multiplier0, shared_multiplier1,
                  shared_multiplier2, shared_multiplier3, shared_multiplier4,
                  shared_multiplier5, shared_multiplier6, shared_multiplier7, M * N,
                  bypassSIMD);
    uint32_t t2 = rdcycle();
    set_gemmx_streamer_start();
    set_gemmx_start();
    wait_gemmx_and_streamer();
    uint32_t t3 = rdcycle();

    uint32_t err = bypassSIMD ? check_gemmx_result_D32(local_d32, D32, Batch, M, N, false)
                              : check_gemmx_result_D8(local_d8, D8, Batch, M, N, false);
    kul_result[0] = 0xC0FFEE00u;            // marker: kernel ran
    kul_result[1] = err;
    kul_result[2] = t3 - t2;                // start..done of streamer+GeMMX (cluster clk cycles)
    kul_result[3] = t1 - t0;                // core copy L3->TCDM
    kul_result[4] = read_gemmx_perf_counter();
    kul_result[5] = read_gemmx_streamer_perf_counter();
    return (int32_t)(err << 1);             // bootrom ORs in bit 0
}
