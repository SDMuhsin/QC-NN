"""Switch qc18.train / qc18.verify to CIFAR-100 without editing qc18: rebinds their module globals
split, test, prep (-> qc18b.data) and QCResNet18 (-> num_classes=100; covers the student, the KD teacher in
qc18.train.main and qc18.verify.load).  qc18.verify.accuracy is qc18.train.accuracy, which uses qc18.train.prep."""
import functools

import qc18.train
import qc18.verify
from qc18.model import QCResNet18

from . import data


@functools.wraps(QCResNet18, updated=())
def QCResNet18_100(*args, **kw):
    kw.setdefault("num_classes", data.NUM_CLASSES)
    return QCResNet18(*args, **kw)


def apply():
    for mod in (qc18.train, qc18.verify):
        mod.split, mod.test, mod.prep, mod.QCResNet18 = data.split, data.test, data.prep, QCResNet18_100
