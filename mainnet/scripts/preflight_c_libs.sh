#!/bin/bash
# Preflight C library rebuild for a cardano-node upgrade.
#
# Resolves iohk-nix-pinned versions of libsodium, secp256k1, and blst for
# the given cardano-node tag (via the IOG dynamic-version cascade), then
# rebuilds and installs them. Also removes the stale libsecp256k1.so.0 and
# refreshes ldconfig.
#
# WARNING: this script removes libsecp256k1.so.0 from /usr/local/lib.
# The currently-running cardano-node 10.x links against .so.0; it survives
# via mmap as long as the process keeps running, but ANY restart will fail
# until a new binary linked against .so.2 is deployed. Run this ONLY during
# an upgrade window, immediately before update_node_binaries.sh.
#
# Usage: ./preflight_c_libs.sh <cardano-node-tag>
# Example: ./preflight_c_libs.sh 11.0.1

set -o pipefail

NOW=$(date +"%Y%m%d_%H%M%S")
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"

# Default download path under ROOT_PATH; override with DOWNLOAD_PATH env var if needed
DOWNLOAD_PATH="${DOWNLOAD_PATH:-$ROOT_PATH/download}"

if [[ $# -ne 1 || -z "$1" ]]; then
    echo "Usage: $0 <cardano-node-tag>"
    echo "Example: $0 11.0.1"
    exit 2
fi
VERSION="$1"

echo "PREFLIGHT C LIBS for cardano-node $VERSION"
echo "SCRIPT_DIR:    $SCRIPT_DIR"
echo "ROOT_PATH:     $ROOT_PATH"
echo "DOWNLOAD_PATH: $DOWNLOAD_PATH"
echo

# shellcheck source=/dev/null
source "$NS_PATH/utils.sh"

echo "WARNING: This will rebuild libsecp256k1 to its iohk-nix pin for $VERSION"
echo "(SONAME bump .so.0 -> .so.2) and REMOVE the existing libsecp256k1.so.0."
echo
echo "The currently-running cardano-node will keep working via mmap but will"
echo "FAIL ON NEXT RESTART until a new binary linked against .so.2 is deployed."
echo
echo "Run this ONLY immediately before update_node_binaries.sh $VERSION."
echo
if ! promptyn "Continue? (y/n)"; then
    echo "Aborted."
    exit 1
fi

# -------- 1. Resolve C lib versions from iohk-nix --------
echo
echo "---------------- Resolving versions from iohk-nix flake.lock ----------------"
IOHKNIX_VERSION=$(curl -s https://raw.githubusercontent.com/IntersectMBO/cardano-node/$VERSION/flake.lock | jq -r '.nodes.iohkNix.locked.rev')
if [[ -z "$IOHKNIX_VERSION" || "$IOHKNIX_VERSION" == "null" ]]; then
    echo "ERROR: failed to resolve IOHKNIX_VERSION for cardano-node $VERSION"
    echo "(Is the tag '$VERSION' published in IntersectMBO/cardano-node?)"
    exit 1
fi
SODIUM_VERSION=$(curl -s https://raw.githubusercontent.com/input-output-hk/iohk-nix/$IOHKNIX_VERSION/flake.lock | jq -r '.nodes.sodium.original.rev')
SECP256K1_VERSION=$(curl -s https://raw.githubusercontent.com/input-output-hk/iohk-nix/$IOHKNIX_VERSION/flake.lock | jq -r '.nodes.secp256k1.original.ref')
BLST_VERSION=$(curl -s https://raw.githubusercontent.com/input-output-hk/iohk-nix/$IOHKNIX_VERSION/flake.lock | jq -r '.nodes.blst.original.ref')

echo "IOHKNIX_VERSION:   $IOHKNIX_VERSION"
echo "SODIUM_VERSION:    $SODIUM_VERSION"
echo "SECP256K1_VERSION: $SECP256K1_VERSION"
echo "BLST_VERSION:      $BLST_VERSION"
echo

mkdir -p "$DOWNLOAD_PATH"
cd "$DOWNLOAD_PATH" || exit 1

# -------- 2. libsodium (skip if already at correct commit) --------
echo "---------------- libsodium ($SODIUM_VERSION) ----------------"
[ -d libsodium ] || git clone https://github.com/intersectmbo/libsodium
cd libsodium && git fetch --all
CURRENT_SODIUM=$(git rev-parse HEAD 2>/dev/null || echo "")
if [[ "$CURRENT_SODIUM" != "$SODIUM_VERSION" ]]; then
    git checkout "$SODIUM_VERSION"
    ./autogen.sh && ./configure && make && sudo make install
else
    echo "libsodium already at $SODIUM_VERSION, skipping rebuild"
fi
cd ..

# -------- 3. secp256k1 --------
echo
echo "---------------- secp256k1 ($SECP256K1_VERSION) ----------------"
[ -d secp256k1 ] || git clone https://github.com/bitcoin-core/secp256k1.git
cd secp256k1 && git fetch --all --tags && git checkout "$SECP256K1_VERSION"
./autogen.sh && ./configure --enable-module-schnorrsig --enable-experimental
make && make check && sudo make install
cd ..

# -------- 4. blst --------
echo
echo "---------------- blst ($BLST_VERSION) ----------------"
[ -d blst ] || git clone https://github.com/supranational/blst
cd blst && git fetch --all --tags && git checkout "$BLST_VERSION"
./build.sh
BLST_PC_VERSION="${BLST_VERSION#v}"
cat > libblst.pc <<EOF
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libblst
Description: Multilingual BLS12-381 signature library
URL: https://github.com/supranational/blst
Version: $BLST_PC_VERSION
Cflags: -I\${includedir}
Libs: -L\${libdir} -lblst
EOF
sudo cp libblst.pc /usr/local/lib/pkgconfig/
sudo cp bindings/blst_aux.h bindings/blst.h bindings/blst.hpp /usr/local/include/
sudo cp libblst.a /usr/local/lib/
sudo chmod u=rw,go=r /usr/local/{lib/{libblst.a,pkgconfig/libblst.pc},include/{blst.{h,hpp},blst_aux.h}}
cd ..

# -------- 5. Stale SONAME cleanup + ld cache refresh --------
echo
echo "---------------- Cleanup stale .so.0 + ldconfig ----------------"
sudo rm -f /usr/local/lib/libsecp256k1.so.0 /usr/local/lib/libsecp256k1.so.0.0.0
sudo ldconfig

# -------- 6. Verify --------
echo
echo "---------------- Post-install verification ----------------"
echo "libsodium:   $(pkg-config --modversion libsodium 2>&1)"
echo "secp256k1:   $(pkg-config --modversion libsecp256k1 2>&1)"
echo "blst:        $(pkg-config --modversion libblst 2>&1)"
echo
echo "ldconfig sees:"
ldconfig -p | grep -E 'libsecp256k1|libsodium|libblst'
echo
echo "✓ C libs ready for cardano-node $VERSION build."
echo "  Next step: $NS_PATH/update_node_binaries.sh $VERSION"
