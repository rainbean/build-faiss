#!/usr/bin/env bash
# Build FAISS for ARM64 linked against Arm Performance Libraries (ArmPL).
# Intended to run natively on DGX Spark or any aarch64 host with ArmPL installed.
#
# Usage:
#   ./scripts/build-arm64-armpl.sh [output_filename]
#   ARMPL_DIR=/opt/arm/armpl_24.10_gcc ./scripts/build-arm64-armpl.sh
#
# Run check-install-armpl.sh first if ArmPL is not yet installed.

set -e

ARMPL_DIR="${ARMPL_DIR:-/opt/arm/armpl_latest}"
DIST_PATH=dist

# ── Validate ArmPL ───────────────────────────────────────────────────────────

if [ ! -f "${ARMPL_DIR}/lib/libarmpl.so" ]; then
    echo "ERROR: libarmpl.so not found at ${ARMPL_DIR}/lib/"
    echo "Set ARMPL_DIR to your ArmPL installation root, or run:"
    echo "  ./scripts/check-install-armpl.sh"
    exit 1
fi

echo "Using ArmPL: ${ARMPL_DIR}"

# ── Build ────────────────────────────────────────────────────────────────────

echo "::group::Configure CMake and Build ..."
rm -fr build dist
cmake -Bbuild \
    -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${DIST_PATH}" \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DFAISS_ENABLE_GPU=OFF \
    -DBUILD_TESTING=OFF \
    -DBLA_VENDOR=Arm \
    -DBLAS_LIBRARIES="${ARMPL_DIR}/lib/libarmpl.so" \
    -DLAPACK_LIBRARIES="${ARMPL_DIR}/lib/libarmpl.so" \
    -DBLAS_INCLUDE_DIRS="${ARMPL_DIR}/include" \
    -DBUILD_SHARED_LIBS=ON \
    faiss

cmake --build build -j "$(nproc)" -t install
echo "::endgroup::"

# ── Verify linkage ───────────────────────────────────────────────────────────

echo "::group::Verify linkage ..."
echo "--- file ---"
file "${DIST_PATH}/lib/libfaiss.so"
echo "--- ldd ---"
ldd "${DIST_PATH}/lib/libfaiss.so"
echo "::endgroup::"

# ── Pack ─────────────────────────────────────────────────────────────────────

echo "::group::Pack artifacts ..."
TARGET=${1:-'faiss-linux-arm64-armpl.tar.zst'}
tar "-I zstd -3 -T4 --long=27" -cf "$TARGET" \
    -C "$DIST_PATH" $(cd "$DIST_PATH"; echo *)
echo "Artifact: $TARGET"
echo "::endgroup::"
