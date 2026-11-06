// Result block in the memory island, written by cluster core 0, read by the host / testbench.
#ifndef NN_RESULT_H
#define NN_RESULT_H
#include <stdint.h>
#include "nn_net.h"
typedef struct {
    uint32_t marker;                              // 0xC0FFEE00 once the run finished
    uint32_t errors;                              // checksum + logit mismatches
    uint32_t first_bad;                           // (image << 8) | step of the first mismatch
    uint32_t cycles[NN_N_IMAGES][NN_N_STEPS];     // mcycle per step (checks excluded)
    uint32_t total[NN_N_IMAGES];                  // mcycle per image (checks excluded)
    int32_t logits[NN_N_IMAGES][NN_N_CLASSES];
    uint32_t pred[NN_N_IMAGES];
    uint32_t gemmx_perf[NN_N_STEPS];              // GeMMX / streamer busy counters, image 0
    uint32_t streamer_perf[NN_N_STEPS];
} nn_result_t;
extern volatile nn_result_t nn_result;
#endif
