// chimera host (CVA6) program: offload the ResNet-8 run to the KUL cluster (cluster 3).
// Exit code (JTAG EOC): 0 = every step checksum and every logit bit-exact vs the reference.
#include <stdint.h>
#include "soc_addr_map.h"
#include "regs/soc_ctrl.h"
#include "offload.h"
#include "kul_chimera.h"
#include "nn_result.h"

extern void nn_entry(void);
extern void nn_trap(void);
volatile uint32_t host_result[2];

int main(void) {
    volatile uint8_t *regPtr = (volatile uint8_t *)SOC_CTRL_BASE;
    nn_result.marker = 0;
    setupInterruptHandler(nn_trap);
    setClusterReset((uint8_t *)regPtr, KUL_CLUSTER_IDX, 0);
    setClusterClockGating((uint8_t *)regPtr, KUL_CLUSTER_IDX, 0);
    offloadToCluster(nn_entry, KUL_CLUSTER_IDX);
    uint32_t ret = waitForCluster(KUL_CLUSTER_IDX);   // (err != 0) << 1 | 1
    host_result[0] = ret;
    host_result[1] = nn_result.errors;
    if (nn_result.marker != 0xC0FFEE00u) return 2;    // cluster did not finish
    if (nn_result.errors != 0 || ret != 1) return 3;  // mismatch vs reference
    return 0;
}
