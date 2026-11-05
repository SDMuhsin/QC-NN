#ifndef KUL_CHIMERA_H
#define KUL_CHIMERA_H
// KUL cluster = chimera external cluster 3 (KULCLUSTERIDX): AXI region 0x4060_0000..0x4080_0000.
// SNAX snitch_cluster maps its TCDM (128 KiB) at cluster_base_addr_i.
#define KUL_CLUSTER_IDX 3
#define KUL_TCDM_BASE   0x40600000u
#define KUL_TCDM_SIZE   0x00020000u
#endif
