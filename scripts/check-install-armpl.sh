#!/usr/bin/env bash
# Checks for an existing ArmPL installation on the current machine.
# If not found, installs Arm Performance Libraries via the official Arm apt repository.
# Run this on DGX Spark before running build-arm64-armpl.sh.
#
# Reference: https://learn.arm.com/install-guides/armpl/

set -e

# ── 1. Search for existing installation ─────────────────────────────────────

echo "=== Searching for ArmPL installation ==="

ARMPL_LIB=""

for dir in /opt/arm /usr/arm /usr/local/arm; do
    hit=$(find "$dir" -name "libarmpl.so" 2>/dev/null | head -1)
    if [ -n "$hit" ]; then
        ARMPL_LIB="$hit"
        break
    fi
done

if [ -z "$ARMPL_LIB" ]; then
    ARMPL_LIB=$(ldconfig -p | awk '/libarmpl\.so /{print $NF}' | head -1)
fi

if [ -n "$ARMPL_LIB" ]; then
    ARMPL_DIR=$(dirname "$(dirname "$ARMPL_LIB")")
    echo "Found: $ARMPL_LIB"
    echo ""
    echo "ARMPL_DIR=$ARMPL_DIR"
    echo ""
    echo "Use with the build script:"
    echo "  ARMPL_DIR=$ARMPL_DIR ./scripts/build-arm64-armpl.sh"
    exit 0
fi

# ── 2. Not found — install via Arm apt repository ───────────────────────────

echo "ArmPL not found. Installing via Arm apt repository ..."
echo ""

# Populate $NAME, $VERSION_ID, $VERSION_CODENAME from the OS
. /etc/os-release

REPO_BASE="https://developer.arm.com/packages/arm-toolchains:${NAME,,}-${VERSION_ID/%.*/}/${VERSION_CODENAME}"

echo "Adding Arm apt repository for ${NAME} ${VERSION_ID} (${VERSION_CODENAME}) ..."
curl -fsSL "${REPO_BASE}/Release.key" \
    | sudo tee /etc/apt/trusted.gpg.d/developer-arm-com.asc > /dev/null
echo "deb ${REPO_BASE}/ ./" \
    | sudo tee /etc/apt/sources.list.d/developer-arm-com.list > /dev/null

sudo apt-get update -q
sudo apt-get install -y arm-performance-libraries

# ── 3. Verify ────────────────────────────────────────────────────────────────

echo ""
echo "=== Verifying installation ==="

ARMPL_LIB=$(find /opt/arm -name "libarmpl.so" 2>/dev/null | head -1)

if [ -z "$ARMPL_LIB" ]; then
    echo "ERROR: libarmpl.so not found under /opt/arm after installation."
    exit 1
fi

ARMPL_DIR=$(dirname "$(dirname "$ARMPL_LIB")")
echo "Installed: $ARMPL_LIB"
echo ""
echo "ARMPL_DIR=$ARMPL_DIR"
echo ""
echo "Use with the build script:"
echo "  ARMPL_DIR=$ARMPL_DIR ./scripts/build-arm64-armpl.sh"
