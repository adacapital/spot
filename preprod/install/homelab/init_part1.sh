#!/bin/bash
set -euo pipefail

# -------------------- globals --------------------
NOW="$(date +"%Y%m%d_%H%M%S")"
TOPO_FILE="$HOME/pool_topology"

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
SPOT_DIR="$(realpath "$(dirname "$PARENT_DIR")")"
CONFIG_DIR="$SPOT_DIR/install/config"
NS_PATH="$SPOT_DIR/scripts"

echo "INIT SCRIPT STARTING..."
echo "SCRIPT_DIR:  $SCRIPT_DIR"
echo "SPOT_DIR:    $SPOT_DIR"
echo "CONFIG_DIR:  $CONFIG_DIR"
echo "NS_PATH:     $NS_PATH"

# importing utility functions
# shellcheck source=/dev/null
source "$NS_PATH/utils.sh"

echo
echo '---------------- Reading pool topology file and preparing a few things... ----------------'

read -r ERROR NODE_TYPE BP_IP RELAYS < <(get_topo "$TOPO_FILE")
# shellcheck disable=SC2206
RELAYS=($RELAYS)

cnt=${#RELAYS[@]}
let cnt1="$cnt/3"
let cnt2="$cnt1 + $cnt1"

RELAY_IPS=( "${RELAYS[@]:0:$cnt1}" )
RELAY_NAMES=( "${RELAYS[@]:$cnt1:$cnt1}" )
RELAY_IPS_PUB=( "${RELAYS[@]:$cnt2:$cnt1}" )

if [[ "$ERROR" == "none" ]]; then
  if [[ -z "${NODE_TYPE:-}" ]]; then
    echo "Node type not identified, something went wrong."
    echo "Please fix the underlying issue and run init_part1.sh again."
    exit 1
  else
    echo "NODE_TYPE:     $NODE_TYPE"
    echo "RELAY_IPS:     ${RELAY_IPS[*]}"
    echo "RELAY_NAMES:   ${RELAY_NAMES[*]}"
    echo "RELAY_IPS_PUB: ${RELAY_IPS_PUB[*]}"
  fi
else
  echo "ERROR: $ERROR"
  exit 1
fi

echo
echo '---------------- Keeping vm current with latest security updates ----------------'
sudo unattended-upgrade -d || true

echo
echo '---------------- Installing dependencies ----------------'
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
  automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev \
  libtinfo-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget \
  libncursesw6 libtool autoconf liblmdb-dev \
  bc tcptraceroute curl ca-certificates xz-utils \
  chrony

echo
echo '---------------- Tweaking chrony and sysctl configurations ----------------'
sudo cp /etc/chrony/chrony.conf "/etc/chrony/chrony.conf.$NOW"
sudo cp /etc/sysctl.conf "/etc/sysctl.conf.$NOW"

sudo cp "$CONFIG_DIR/chrony.conf" /etc/chrony/chrony.conf
sudo cp "$CONFIG_DIR/sysctl.conf" /etc/sysctl.conf
sudo sysctl --system
sudo systemctl restart chrony

# -------------------- paths --------------------
DOWNLOAD_PATH="/home/cardano/download"
DOWNLOAD_PATH="$(prompt_input_default DOWNLOAD_PATH "$DOWNLOAD_PATH")"
mkdir -p "$DOWNLOAD_PATH"

CARDANO_NODE_INSTALL_PATH="/home/cardano"
CARDANO_NODE_INSTALL_PATH="$(prompt_input_default CARDANO_NODE_INSTALL_PATH "$CARDANO_NODE_INSTALL_PATH")"
mkdir -p "$CARDANO_NODE_INSTALL_PATH"

# -------------------- cardano-node version --------------------
CARDANO_NODE_TAG="${1:-}"
if [[ -z "$CARDANO_NODE_TAG" ]]; then
  CARDANO_NODE_TAG="$(curl -s https://api.github.com/repos/intersectmbo/cardano-node/releases/latest | jq -r .tag_name)"
fi

if [[ "$NODE_TYPE" == "bp" ]]; then
  echo "Cardano node tag to build: $CARDANO_NODE_TAG"
  if ! promptyn "Proceed with building cardano-node $CARDANO_NODE_TAG ? (y/n)"; then exit 1; fi
fi

# -------------------- ensure env for THIS script run --------------------
echo
echo '---------------- Ensuring PATH / LD_LIBRARY_PATH / PKG_CONFIG_PATH ----------------'

export PATH="$HOME/.ghcup/bin:$HOME/.local/bin:$HOME/.cabal/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

echo "\$PATH:            $PATH"
echo "\$LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "\$PKG_CONFIG_PATH: $PKG_CONFIG_PATH"

# Persist to bashrc (single marker block; idempotent-ish)
if ! grep -q "Added by SPOT init_part1.sh (homelab)" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'EOF'

# Added by SPOT init_part1.sh (homelab)
export PATH="$HOME/.ghcup/bin:$HOME/.local/bin:$HOME/.cabal/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
EOF
fi

# Prefer system-wide loader config for /usr/local/lib (stable for services/non-interactive shells)
echo
echo '---------------- Ensuring /usr/local/lib is registered with the dynamic loader ----------------'
if [[ ! -f /etc/ld.so.conf.d/usr-local-lib.conf ]] || ! grep -q '^/usr/local/lib$' /etc/ld.so.conf.d/usr-local-lib.conf; then
  echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/usr-local-lib.conf >/dev/null
fi
sudo ldconfig
ldconfig -p | grep -i sodium || true

# -------------------- GHC/Cabal (BP only) --------------------
echo
echo '---------------- Installing Cabal & GHC dependency (BP only) ----------------'

# CoinCashew-aligned toolchain for modern Cardano builds
BOOTSTRAP_HASKELL_GHC_VERSION="9.6.7"
BOOTSTRAP_HASKELL_CABAL_VERSION="3.12.1.0"

if [[ "$NODE_TYPE" == "bp" ]]; then
  need_haskell=0

  if ! command -v ghcup >/dev/null 2>&1; then
    need_haskell=1
  fi
  if ! command -v ghc >/dev/null 2>&1; then
    need_haskell=1
  fi
  if ! command -v cabal >/dev/null 2>&1; then
    need_haskell=1
  fi

  if [[ $need_haskell -eq 0 ]]; then
    echo "Detected:"
    ghc --version || true
    cabal --version || true

    if ! ghc --version | grep -q "$BOOTSTRAP_HASKELL_GHC_VERSION"; then
      echo "GHC is not $BOOTSTRAP_HASKELL_GHC_VERSION -> will install/set correct version."
      need_haskell=1
    fi
    if ! cabal --version | grep -q "$BOOTSTRAP_HASKELL_CABAL_VERSION"; then
      echo "Cabal is not $BOOTSTRAP_HASKELL_CABAL_VERSION -> will install/set correct version."
      need_haskell=1
    fi
  fi

  if [[ $need_haskell -eq 1 ]]; then
    export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
    export BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1
    export BOOTSTRAP_HASKELL_ADJUST_BASHRC=1

    curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
    export PATH="$HOME/.ghcup/bin:$HOME/.local/bin:$HOME/.cabal/bin:$PATH"

    echo "Installing ghc $BOOTSTRAP_HASKELL_GHC_VERSION"
    ghcup install "ghc" "$BOOTSTRAP_HASKELL_GHC_VERSION" || true
    ghcup set "ghc" "$BOOTSTRAP_HASKELL_GHC_VERSION"

    echo "Installing cabal $BOOTSTRAP_HASKELL_CABAL_VERSION"
    ghcup install "cabal" "$BOOTSTRAP_HASKELL_CABAL_VERSION" || true
    ghcup set "cabal" "$BOOTSTRAP_HASKELL_CABAL_VERSION"
  fi

  echo "Final toolchain:"
  which ghc || true
  which cabal || true
  ghc --version
  cabal --version

  echo
  if ! promptyn "Please confirm you want to continue? (y/n)"; then
    echo "Ok bye!"
    exit 1
  fi
else
  echo "Node is not BP; skipping GHC/Cabal install."
fi

# -------------------- libsodium --------------------
echo
echo '---------------- Libsodium dependency ----------------'

# Remove distro libsodium-dev if present to avoid conflicts (CoinCashew-style hygiene)
if dpkg -s libsodium-dev >/dev/null 2>&1; then
  sudo apt-get remove -y libsodium-dev || true
fi

export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

if pkg-config --exists libsodium; then
  echo "libsodium found via pkg-config, no installation required."
  pkg-config --modversion libsodium || true
else
  echo "libsodium not found via pkg-config, installing Intersect/IOG libsodium fork..."
  mkdir -p "$DOWNLOAD_PATH"
  cd "$DOWNLOAD_PATH"

  if [[ ! -d libsodium ]]; then
    git clone https://github.com/IntersectMBO/libsodium
  fi

  cd libsodium
  git fetch --all --tags
  git reset --hard
  git clean -fdx
  git checkout dbb48cc

  ./autogen.sh
  ./configure
  make -j"$(nproc)"
  sudo make install
  sudo ldconfig
  ldconfig -p | grep -i sodium || true

  if pkg-config --exists libsodium; then
    echo "OK: libsodium now available."
    pkg-config --modversion libsodium || true
    pkg-config --cflags libsodium || true
    pkg-config --libs libsodium || true
  else
    echo "ERROR: libsodium still not available after install."
    echo "Debug:"
    echo "  export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:\$PKG_CONFIG_PATH"
    echo "  pkg-config --list-all | grep -i sodium"
    exit 1
  fi
fi

# -------------------- secp256k1 --------------------
echo
echo '---------------- secp256k1 dependency ----------------'
if ldconfig -p | grep -qE 'libsecp256k1\.so'; then
  echo "secp256k1 lib found, no installation required."
else
  echo "secp256k1 lib not found, installing..."
  mkdir -p "$DOWNLOAD_PATH"
  cd "$DOWNLOAD_PATH"

  if [[ ! -d secp256k1 ]]; then
    git clone https://github.com/bitcoin-core/secp256k1.git
  fi

  cd secp256k1
  git fetch --all --tags
  git reset --hard
  git clean -fdx
  git checkout ac83be33

  ./autogen.sh
  ./configure --enable-module-schnorrsig --enable-experimental
  make -j"$(nproc)"
  make check
  sudo make install
  sudo ldconfig
fi

# -------------------- blst --------------------
echo
echo '---------------- BLST dependency ----------------'

BLST_MIN_VERSION="0.3.14"
BLST_TAG="v0.3.14"

have_blst_ok=0
if pkg-config --exists libblst; then
  current_blst_ver="$(pkg-config --modversion libblst || true)"
  if [[ -n "$current_blst_ver" ]]; then
    # version compare using sort -V
    if [[ "$(printf "%s\n%s\n" "$BLST_MIN_VERSION" "$current_blst_ver" | sort -V | head -n1)" == "$BLST_MIN_VERSION" ]]; then
      have_blst_ok=1
    fi
  fi
fi

if [[ $have_blst_ok -eq 1 ]]; then
  echo "libblst found via pkg-config (version $current_blst_ver) and meets >= $BLST_MIN_VERSION. No installation required."
else
  echo "libblst missing or too old (need >= $BLST_MIN_VERSION). Installing $BLST_TAG ..."
  mkdir -p "$DOWNLOAD_PATH"
  cd "$DOWNLOAD_PATH"

  if [[ ! -d blst ]]; then
    git clone https://github.com/supranational/blst
  fi

  cd blst
  git fetch --all --tags
  git reset --hard
  git clean -fdx
  git checkout "$BLST_TAG"

  # build static lib
  ./build.sh

  # Remove any older pc file to avoid confusion
  sudo rm -f /usr/local/lib/pkgconfig/libblst.pc || true

  cat > libblst.pc <<EOF
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libblst
Description: Multilingual BLS12-381 signature library
URL: https://github.com/supranational/blst
Version: ${BLST_TAG#v}
Cflags: -I\${includedir}
Libs: -L\${libdir} -lblst
EOF

  sudo mkdir -p /usr/local/lib/pkgconfig /usr/local/include
  sudo cp libblst.pc /usr/local/lib/pkgconfig/
  sudo cp bindings/blst_aux.h bindings/blst.h bindings/blst.hpp /usr/local/include/
  sudo cp libblst.a /usr/local/lib
  sudo chmod u=rw,go=r /usr/local/{lib/{libblst.a,pkgconfig/libblst.pc},include/{blst.{h,hpp},blst_aux.h}}
  sudo ldconfig

  echo "Verifying libblst via pkg-config..."
  pkg-config --modversion libblst
  pkg-config --cflags libblst
  pkg-config --libs libblst
fi


# -------------------- build cardano-node (BP only) --------------------
if [[ "$NODE_TYPE" == "bp" ]]; then
  echo
  echo '---------------- Building the node from source ----------------'

  cd "$CARDANO_NODE_INSTALL_PATH"

  if [[ ! -d cardano-node/.git ]]; then
    rm -rf cardano-node
    git clone https://github.com/intersectmbo/cardano-node.git
  fi

  # Always operate on the repo explicitly (clean & deterministic)
  git -C cardano-node fetch --all --recurse-submodules --tags --force
  git -C cardano-node reset --hard
  git -C cardano-node clean -fdx

  if ! git -C cardano-node rev-parse -q --verify "refs/tags/$CARDANO_NODE_TAG" >/dev/null; then
    echo "ERROR: tag '$CARDANO_NODE_TAG' not found locally after fetch."
    echo "Hint: check if the repo uses a 'v' prefix (e.g. v$CARDANO_NODE_TAG) or pick another tag."
    exit 1
  fi

  git -C cardano-node checkout "tags/$CARDANO_NODE_TAG"

  cd "$CARDANO_NODE_INSTALL_PATH/cardano-node"

  echo
  echo '---------------- Cabal package indexes ----------------'
  # Important: keep build aligned with the repo's cabal.project (avoids solver drift).
  cabal update

  # Ensure current shell has env (belt-and-braces)
  export PATH="$HOME/.ghcup/bin:$HOME/.local/bin:$HOME/.cabal/bin:$PATH"
  export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

  cabal configure --with-compiler="ghc-${BOOTSTRAP_HASKELL_GHC_VERSION}"

  # Keep your existing override (VRF external libsodium flag off)
  echo -e "package cardano-crypto-praos\n  flags: -external-libsodium-vrf" > cabal.project.local

  # Build using the project file to stay in sync with pinned index-state/CHaP config.
  echo
  echo '---------------- Building cardano-node ----------------'
  cabal build all --project-file=cabal.project -j"$(nproc)"

  echo
  echo '---------------- Building cardano-cli ----------------'
  cabal build cardano-cli -j"$(nproc)"

  echo
  echo '---------------- Installing binaries to ~/.local/bin ----------------'
  mkdir -p "$HOME/.local/bin"
  NODE_BIN="$(cabal exec -- which cardano-node 2>/dev/null || true)"
  CLI_BIN="$(cabal exec -- which cardano-cli 2>/dev/null || true)"
  cp -p "$NODE_BIN" "$HOME/.local/bin/cardano-node"
  cp -p "$CLI_BIN"  "$HOME/.local/bin/cardano-cli"

  "$HOME/.local/bin/cardano-node" --version
  "$HOME/.local/bin/cardano-cli" --version
fi

echo
echo "INIT_PART1 IS COMPLETED."
