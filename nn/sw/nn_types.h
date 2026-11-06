// Types shared by the runtime (nn_cluster.c) and the compiler output (build/gen/nn_net.c).
#ifndef NN_TYPES_H
#define NN_TYPES_H
#include <stdint.h>

enum { NN_INPUT = 0, NN_CONV = 1, NN_ADD = 2, NN_POOLFC = 3 };

// One GeMMX call: streamer + GeMMX CSR values, in the argument order of snax-gemmx-lib.c.
typedef struct {
    int32_t Aslstride0, Aslstride1, Atlbound0, Atlstride0, Atlbound1, Atlstride1, Atlbound2,
        Atlstride2, Atlbound3, Atlstride3, Atlbound4, Atlstride4, Atlbound5, Atlstride5,
        set_addr_remap_index_A;
    int32_t Bslstride0, Bslstride1, Btlbound0, Btlstride0, Btlbound1, Btlstride1, Btlbound2,
        Btlstride2, set_addr_remap_index_B;
    int32_t D8slstride0, D8slstride1, D8tlbound0, D8tlstride0, D8tlbound1, D8tlstride1,
        D8tlbound2, D8tlstride2, set_addr_remap_index_D8;
    int32_t Cslstride0, Cslstride1, Ctlbound0, Ctlstride0, Ctlbound1, Ctlstride1, Ctlbound2,
        Ctlstride2, set_addr_remap_index_C;
    int32_t D32slstride0, D32slstride1, D32tlbound0, D32tlstride0, D32tlbound1, D32tlstride1,
        D32tlbound2, D32tlstride2, set_addr_remap_index_D32;
    int32_t delta_local_a, delta_local_b, delta_local_d8, delta_local_c, delta_local_d32;
    int32_t bypassSIMD, transposed_A, transposed_B, channel_en_C, broadcast_C;
    int32_t K, N, M;
    uint32_t subtractions, csr0, csr1, shift0, shift1;
    int32_t mult[8];
} nn_conv_t;

// Residual add + requant on the cores: out = clamp((((a-za)*ma + (b-zb)*mb + 2^15) >> 16) + zo, lo, 127)
typedef struct {
    uint32_t a, b, out;              // TCDM offsets of the padded tensors
    int32_t za, ma, zb, mb, zo, lo;
    uint32_t C8, H, Wp;
} nn_add_t;

// Global average pool (as a channel sum) + FC -> int32 logits
typedef struct {
    uint32_t in, C8, H, Wp;          // add3 tensor
    int32_t zp;
    uint32_t w, bias;                // TCDM offsets (int8 [10][64], int32 [10])
    uint32_t n_out, n_in;
} nn_poolfc_t;

// Constant data DMA'd from the memory island into TCDM at the start of step `issue`.
typedef struct {
    const uint8_t *src;
    uint32_t dst, size, issue;
} nn_blob_t;

typedef struct {
    uint32_t kind;
    int32_t blob;                    // blob that must have landed before the step, or -1
    const void *p;                   // nn_conv_t / nn_add_t / nn_poolfc_t
    uint32_t out, out_C8, out_H, out_Wp;  // output tensor (checksum, border fill)
    int32_t border_zp;               // fill the output border with this zp first, or 999
} nn_step_t;

#endif
