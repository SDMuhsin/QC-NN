#!/usr/bin/env python3
"""Data generator for sw/dnn/conv2d, wrapping the upstream datagen.py.

The upstream generator initialises the output buffer `conv2d_ofmap_dram` with
the golden result, so a kernel that never writes its output would still read
back "correct" data. This wrapper emits the identical header but with the
output buffer zero-filled, making the post-simulation check meaningful.
Requires SNITCH_WS (staged snitch_cluster workspace) in the environment.
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.join(os.environ['SNITCH_WS'], 'sw/dnn/conv2d/scripts'))
import datagen  # noqa: E402  (upstream sw/dnn/conv2d/scripts/datagen.py)

_upstream_def = datagen.format_array_definition


def _format_array_definition(dtype, uid, array, *args, **kwargs):
    if uid == 'conv2d_ofmap_dram':
        array = np.zeros_like(array)
    return _upstream_def(dtype, uid, array, *args, **kwargs)


datagen.format_array_definition = _format_array_definition

if __name__ == '__main__':
    datagen.main()
