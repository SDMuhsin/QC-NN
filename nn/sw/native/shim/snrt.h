// Host-build stand-in for the snRuntime header (see ../native.c): CSR accesses are no-ops.
#ifndef NN_NATIVE_SNRT_H
#define NN_NATIVE_SNRT_H
#include <stdint.h>
#include <stddef.h>
#include "kul_chimera.h"
static inline void csrw_ss(uint32_t a, uint32_t v) { (void)a; (void)v; }
static inline uint32_t csrr_ss(uint32_t a) { (void)a; return 0; }
static inline uint32_t snrt_l1_next(void) { return KUL_TCDM_BASE; }
#endif
