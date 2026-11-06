// Cluster entry (both KUL cores jump here from chimera's snitch bootrom; core 1 after core 0
// wakes it).  The bootrom never sets sp: give each hart a stack at the top of the TCDM
// (core 0: top, core 1: top - 1.5 KiB; the mailbox sits below them, see nn_cluster.c).
#include "kul_chimera.h"
.section .text
.global nn_entry
nn_entry:
    csrr a0, mhartid
    li   t0, KUL_HART0
    sub  t0, a0, t0                 // core index 0 / 1
    li   t1, 1536
    mul  t0, t0, t1
    li   sp, KUL_TCDM_BASE + KUL_TCDM_SIZE - 16
    sub  sp, sp, t0
    sw   ra, 12(sp)
    call nn_cluster_main            // a0 = mhartid
    lw   ra, 12(sp)
    ret

// Software-interrupt handler (chimera SNITCH_INTR_HANDLER_ADDR): clear this hart's CLINT msip.
.global nn_trap
nn_trap:
    csrr t0, mhartid
    slli t0, t0, 2
    li   t1, 0x02040000
    add  t0, t0, t1
    sw   zero, 0(t0)
    ret
