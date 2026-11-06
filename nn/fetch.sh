#!/usr/bin/env bash
# Download the inputs that are kept out of git into nn/data/:
#   pretrainedResnet.h5   MLPerf Tiny ResNet-8 (mlcommons/tiny, image_classification)
#   cifar-10-batches-py/  CIFAR-10 (python version)
set -euo pipefail
D=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data
mkdir -p "$D" && cd "$D"
H5=https://github.com/mlcommons/tiny/raw/master/benchmark/training/image_classification/trained_models/pretrainedResnet.h5
[ -f pretrainedResnet.h5 ] || curl -sSL -o pretrainedResnet.h5 "$H5"
if [ ! -d cifar-10-batches-py ]; then
  curl -sSL -o cifar-10-python.tar.gz https://www.cs.toronto.edu/~kriz/cifar-10-python.tar.gz
  echo "c58f30108f718f92721af3b95e74349a  cifar-10-python.tar.gz" | md5sum -c -
  tar xzf cifar-10-python.tar.gz && rm cifar-10-python.tar.gz
fi
ls -l "$D"
