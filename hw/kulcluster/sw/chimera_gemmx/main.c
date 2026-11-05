// chimera host (CVA6) program: offload the SNAX GeMM test to the KUL cluster and self-check.
// Exit code (JTAG EOC): 0 = PASS.
#include <stdint.h>
#include "soc_addr_map.h"
#include "regs/soc_ctrl.h"
#include "offload.h"
#include "kul_chimera.h"

extern void kul_entry(void);
extern void kul_trap(void);
extern volatile uint32_t kul_result[8];
volatile uint32_t host_result[4];

int main(void) {
    volatile uint8_t *regPtr = (volatile uint8_t *)SOC_CTRL_BASE;
    for (int i = 0; i < 8; i++) kul_result[i] = 0;
    setupInterruptHandler(kul_trap);
    setClusterReset(regPtr, KUL_CLUSTER_IDX, 0);
    setClusterClockGating(regPtr, KUL_CLUSTER_IDX, 0);
    offloadToCluster(kul_entry, KUL_CLUSTER_IDX);
    uint32_t ret = waitForCluster(KUL_CLUSTER_IDX);   // (err << 1) | 1
    host_result[0] = ret;
    if (kul_result[0] != 0xC0FFEE00u) return 2;      // kernel did not run
    if (kul_result[1] != 0 || ret != 1) return 3;    // mismatches vs golden
    return 0;
}
