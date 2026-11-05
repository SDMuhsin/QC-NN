// Entry points executed by the KUL cluster's core 0 (SNAX GeMMX-control Snitch, mhartid 7).
// chimera's snitch bootrom jumps here with sp never initialised (X in 4-state sim), so set up a
// stack at the top of the cluster's TCDM before calling C. sp is not saved/restored: the bootrom
// does not use it, and copying the X value would trip Snitch's RegWriteKnown assertion.
#include "kul_chimera.h"
.section .text
.global kul_entry
kul_entry:
    li   sp, KUL_TCDM_BASE + KUL_TCDM_SIZE - 16
    sw   ra, 12(sp)
    call kul_gemm
    lw   ra, 12(sp)
    ret

// Software-interrupt handler (installed via chimera's SNITCH_INTR_HANDLER_ADDR register):
// clear this hart's CLINT msip. Stack-free on purpose.
.global kul_trap
kul_trap:
    csrr t0, mhartid
    slli t0, t0, 2
    li   t1, 0x02040000
    add  t0, t0, t1
    sw   zero, 0(t0)
    ret
