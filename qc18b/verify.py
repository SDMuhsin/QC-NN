"""qc18.verify on CIFAR-100 (see qc18b.c100):  python3 -m qc18b.verify CKPT [--test]
--dense: evaluate a dense checkpoint instead (val + test with --test; no QC check), as qc18/final.sh verify dense."""
import sys

import torch

import qc18.train
import qc18.verify

from . import c100


def dense(path, do_test):
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    ck, m = qc18.verify.load(path, "cuda")
    print(f"{path}: dense, epoch {ck['epoch']}, checkpoint val {100 * ck['val']:.2f} %")
    print(f"val accuracy (fp32) {100 * qc18.train.accuracy(m, *qc18.verify.split('cuda')[1]):.2f} %")
    if do_test:
        print(f"test accuracy (fp32) {100 * qc18.train.accuracy(m, *qc18.verify.test('cuda')):.2f} %")
    return 0


if __name__ == "__main__":
    c100.apply()
    if "--dense" in sys.argv:
        args = [s for s in sys.argv[1:] if s != "--dense"]
        sys.exit(dense([s for s in args if not s.startswith("--")][0], "--test" in args))
    sys.exit(qc18.verify.main())
