// Minimal stand-in for the SNAX snRuntime header, enough for snax-gemmx-lib.c when the KUL
// cluster runs bare-metal inside chimera (no snRuntime; entered from chimera's snitch bootrom).
#ifndef KUL_SNRT_SHIM_H
#define KUL_SNRT_SHIM_H
#include <stdint.h>
#include <stddef.h>
#include "kul_chimera.h"
// read_csr/write_csr as in riscv-opcodes encoding.h (used by SNAX csr.h)
#define read_csr(reg) ({ unsigned long __tmp; asm volatile ("csrr %0, " #reg : "=r"(__tmp)); __tmp; })
#define write_csr(reg, val) ({ asm volatile ("csrw " #reg ", %0" :: "rK"(val)); })
#include "csr.h"   // SNAX csrr_ss/csrw_ss (sw/snRuntime/src/csr.h of the pinned snax_cluster)
static inline uint32_t snrt_l1_next(void) { return KUL_TCDM_BASE; }
static inline int printf(const char *f, ...) { (void)f; return 0; }
#endif
