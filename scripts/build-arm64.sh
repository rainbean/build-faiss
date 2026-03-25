#!/usr/bin/env bash

# abort on any error
set -e

DIST_PATH=dist

# configure build and compile
echo "::group::Configure CMake and Build ..."
rm -fr build dist
cmake -Bbuild \
    -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${DIST_PATH}" \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DFAISS_ENABLE_GPU=OFF \
    -DBUILD_TESTING=OFF \
    -DBLA_VENDOR=OpenBLAS \
    -DBUILD_SHARED_LIBS=ON \
    faiss

cmake --build build -j "$(nproc)" -t install
echo "::endgroup::"

# pack binary
echo "::group::Pack artifacts ..."
TARGET=${1:-'faiss-linux-arm64.tar.zst'}
tar "-I zstd -3 -T4 --long=27" -cf "$TARGET" \
    -C "$DIST_PATH" $(cd "$DIST_PATH"; echo *)
echo "::endgroup::"
