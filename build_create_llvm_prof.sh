#!/bin/bash

set -eux
DDIR="$(cd "$(dirname "$0")"; pwd)"
LLVM_INSTALL="$1"

mkdir -p "${DDIR}/build-create_llvm_prof"
cd "${DDIR}/build-create_llvm_prof"
git clone --recursive https://github.com/google/autofdo.git
cd autofdo && git checkout "origin/main"
cd "${DDIR}/build-create_llvm_prof"
mkdir -p bin && cd bin
cmake -G Ninja -DCMAKE_INSTALL_PREFIX="." \
      -DCMAKE_C_COMPILER="${LLVM_INSTALL}/bin/clang" \
      -DCMAKE_CXX_COMPILER="${LLVM_INSTALL}/bin/clang++" \
      -DLLVM_PATH="$LLVM_INSTALL" ../autofdo/
ninja
cp ./create_llvm_prof ${DDIR}/
