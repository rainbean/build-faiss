#!/usr/bin/env bash

# abort on any error
set -e

ARCH=$(uname -m)
DIST_PATH=dist

# configure build and compile
echo "::group::Configure CMake and Build ..."
rm -fr build dist
cmake -Bbuild \
    -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${DIST_PATH}" \
    -DCMAKE_INSTALL_RPATH='$ORIGIN' \
    -DCMAKE_IGNORE_PREFIX_PATH="$HOME/mamba" \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DFAISS_ENABLE_GPU=OFF \
    -DBUILD_TESTING=OFF \
    -DBLA_VENDOR=OpenBLAS \
    -DBUILD_SHARED_LIBS=ON \
    faiss

cmake --build build -j "$(nproc)" -t install
echo "::endgroup::"

# bundle OpenBLAS and its Fortran runtime so the artifact is self-contained
echo "::group::Bundle OpenBLAS ..."

# Resolve the real file (not symlinks) and copy it, then recreate symlinks cleanly
OPENBLAS_REAL=$(readlink -f "$(ldconfig -p | awk '/libopenblas\.so\.0 /{print $NF}' | head -1)")
OPENBLAS_DIR=$(dirname "$OPENBLAS_REAL")
OPENBLAS_FILE=$(basename "$OPENBLAS_REAL")
cp "$OPENBLAS_REAL" "$DIST_PATH/lib/"
ln -sf "$OPENBLAS_FILE" "$DIST_PATH/lib/libopenblas.so.0"
ln -sf "$OPENBLAS_FILE" "$DIST_PATH/lib/libopenblas.so"

# libgfortran is a runtime dependency of OpenBLAS (Fortran LAPACK routines)
GFORTRAN_REAL=$(readlink -f "$(ldconfig -p | awk '/libgfortran\.so\.5 /{print $NF}' | head -1)")
GFORTRAN_FILE=$(basename "$GFORTRAN_REAL")
cp "$GFORTRAN_REAL" "$DIST_PATH/lib/"
ln -sf "$GFORTRAN_FILE" "$DIST_PATH/lib/libgfortran.so.5"

# libquadmath is a runtime dependency of libgfortran; x86_64 only (not present on ARM64)
QUADMATH_PATH=$(ldconfig -p | awk '/libquadmath\.so\.0 /{print $NF}' | head -1)
if [ -n "$QUADMATH_PATH" ]; then
    QUADMATH_REAL=$(readlink -f "$QUADMATH_PATH")
    QUADMATH_FILE=$(basename "$QUADMATH_REAL")
    cp "$QUADMATH_REAL" "$DIST_PATH/lib/"
    ln -sf "$QUADMATH_FILE" "$DIST_PATH/lib/libquadmath.so.0"
fi

# rewrite cmake targets to use relative install path
sed -i "s@${OPENBLAS_DIR}@\${_IMPORT_PREFIX}/lib@g" "$DIST_PATH/share/faiss/faiss-targets.cmake"
echo "::endgroup::"

# pack binary
echo "::group::Pack artifacts ..."
TARGET=${1:-"faiss-linux-${ARCH}.tar.zst"}
tar "-I zstd -3 -T4 --long=27" -cf "$TARGET" \
    -C "$DIST_PATH" $(cd "$DIST_PATH"; echo *)
echo "::endgroup::"
