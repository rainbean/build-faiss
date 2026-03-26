#!/usr/bin/env bash
# Checks for an existing ArmPL installation on the current machine.
# If not found, downloads and installs Arm Performance Libraries 24.10.
# Run this on DGX Spark before running build-arm64-armpl.sh.

set -e

ARMPL_VERSION="24.10"
ARMPL_INSTALLER_URL="https://developer.arm.com/-/cdn-downloads/permalink/Arm-Performance-Libraries/Version_${ARMPL_VERSION}/arm-performance-libraries_${ARMPL_VERSION}_deb_gcc.sh"
INSTALL_PREFIX="/opt/arm"

# ── 1. Search for existing installation ─────────────────────────────────────

echo "=== Searching for ArmPL installation ==="

ARMPL_LIB=""

# Search common install roots
for dir in /opt/arm /usr/arm /usr/local/arm; do
    hit=$(find "$dir" -name "libarmpl.so" 2>/dev/null | head -1)
    if [ -n "$hit" ]; then
        ARMPL_LIB="$hit"
        break
    fi
done

# Fall back to ldconfig cache
if [ -z "$ARMPL_LIB" ]; then
    ARMPL_LIB=$(ldconfig -p | awk '/libarmpl\.so /{print $NF}' | head -1)
fi

if [ -n "$ARMPL_LIB" ]; then
    # lib is at <ARMPL_DIR>/lib/libarmpl.so
    ARMPL_DIR=$(dirname "$(dirname "$ARMPL_LIB")")
    echo "Found: $ARMPL_LIB"
    echo ""
    echo "ARMPL_DIR=$ARMPL_DIR"
    echo ""
    echo "Use with the build script:"
    echo "  ARMPL_DIR=$ARMPL_DIR ./scripts/build-arm64-armpl.sh"
    exit 0
fi

# ── 2. Not found — install ───────────────────────────────────────────────────

echo "ArmPL not found. Installing version ${ARMPL_VERSION} ..."
echo ""

INSTALLER=$(mktemp /tmp/armpl_install_XXXXXX.sh)
curl -fsSL "$ARMPL_INSTALLER_URL" -o "$INSTALLER"
chmod +x "$INSTALLER"

# The installer accepts --install-to to set the root directory.
# It will create a versioned subdirectory under that root, e.g.:
#   /opt/arm/armpl_24.10_gcc/
sudo bash "$INSTALLER" --install-to "$INSTALL_PREFIX"
rm -f "$INSTALLER"

# ── 3. Verify ────────────────────────────────────────────────────────────────

echo ""
echo "=== Verifying installation ==="

ARMPL_LIB=$(find "$INSTALL_PREFIX" -name "libarmpl.so" 2>/dev/null | head -1)

if [ -z "$ARMPL_LIB" ]; then
    echo "ERROR: libarmpl.so not found under $INSTALL_PREFIX after installation."
    exit 1
fi

ARMPL_DIR=$(dirname "$(dirname "$ARMPL_LIB")")
echo "Installed: $ARMPL_LIB"
echo ""
echo "ARMPL_DIR=$ARMPL_DIR"
echo ""
echo "Use with the build script:"
echo "  ARMPL_DIR=$ARMPL_DIR ./scripts/build-arm64-armpl.sh"
