// Host (x86, -m32) stand-ins for nn_cluster.c, see native.c.  The TCDM (0x4060_0000) and the
// CLINT page are mmap'ed at their real addresses, so the runtime runs unmodified; core 1's
// jobs are executed inline when core 0 posts them, and DMA becomes a word copy.
#ifndef NN_NATIVE_H
#define NN_NATIVE_H
#define NN_NO_DMA
static inline uint32_t rdcycle(void) { return 0; }
static inline void fence(void) { __asm__ volatile("" ::: "memory"); }
#define NATIVE_SERVE_JOBS() core1_serve()
#endif
