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

# bundle OpenBLAS so the artifact is self-contained at runtime
echo "::group::Bundle OpenBLAS ..."
OPENBLAS_LIB=$(ldconfig -p | awk '/libopenblas\.so\.0 /{print $NF}' | head -1)
OPENBLAS_DIR=$(dirname "$OPENBLAS_LIB")
cp "$OPENBLAS_DIR"/libopenblas.so* "$DIST_PATH/lib/"
sed -i "s@${OPENBLAS_DIR}@\${_IMPORT_PREFIX}/lib@g" "$DIST_PATH/share/faiss/faiss-targets.cmake"
echo "::endgroup::"

# pack binary
echo "::group::Pack artifacts ..."
TARGET=${1:-'faiss-linux-arm64.tar.zst'}
tar "-I zstd -3 -T4 --long=27" -cf "$TARGET" \
    -C "$DIST_PATH" $(cd "$DIST_PATH"; echo *)
echo "::endgroup::"
