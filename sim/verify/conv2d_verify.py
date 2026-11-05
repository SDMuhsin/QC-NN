#!/usr/bin/env python3
"""Self-check for sw/dnn/conv2d against a PyTorch golden model.

Uses the upstream Verifier framework (util/sim/verif_utils.py): runs the
simulation, reads `conv2d_ofmap_dram` back over IPC and compares it to
torch.nn.functional.conv2d on the inputs stored in the ELF.

The kernel (sw/dnn/conv2d/src/conv2d.h) uses HWC tensors: ifmap [IH][IW][CI],
weights [CO][FH][FW][CI], ofmap [OH][OW][CO]; the buffers are therefore
interpreted in that layout (the upstream data is i.i.d. random, so the
reinterpretation leaves the test data valid).
Requires SNITCH_WS (staged snitch_cluster workspace) in the environment.
"""
import os
import sys
import numpy as np
import torch

sys.path.insert(0, os.path.join(os.environ['SNITCH_WS'], 'util/sim'))
from verif_utils import Verifier  # noqa: E402
from data_utils import ctype_from_precision_t  # noqa: E402

LAYER_STRUCT = {k: 'I' for k in (
    'CO', 'CI', 'IH', 'IW', 'OH', 'OW', 'FH', 'FW', 'pad', 'ifmap', 'weights',
    'ofmap', 'TILE_CI', 'cluster2cluster', 'im2col', 'gamma', 'beta', 'dtype')}


class Conv2dVerifier(Verifier):

    OUTPUT_UIDS = ['conv2d_ofmap_dram']
    RTOL = 1e-6

    def __init__(self):
        super().__init__()
        self.layer = self.get_input_from_symbol('layer', LAYER_STRUCT)
        self.ctype = ctype_from_precision_t(self.layer['dtype'])

    def get_actual_results(self):
        return self.get_output_from_symbol(self.OUTPUT_UIDS[0], self.ctype)

    def get_expected_results(self):
        lyr = self.layer
        ifmap = self.get_input_from_symbol('conv2d_ifmap_dram', self.ctype)
        weights = self.get_input_from_symbol('conv2d_weights_dram', self.ctype)
        x = torch.from_numpy(ifmap.reshape(lyr['IH'], lyr['IW'], lyr['CI'])).permute(2, 0, 1)
        w = torch.from_numpy(weights.reshape(lyr['CO'], lyr['FH'], lyr['FW'], lyr['CI']))
        w = w.permute(0, 3, 1, 2)
        pad = (lyr['FH'] - 1) // 2  # as set in main.c
        y = torch.nn.functional.conv2d(x.unsqueeze(0), w, padding=pad, stride=1)[0]
        return y.permute(1, 2, 0).numpy().flatten()  # CHW -> HWC

    def check_results(self, *args):
        return super().check_results(*args, rtol=self.RTOL)


if __name__ == '__main__':
    sys.exit(Conv2dVerifier().main())
