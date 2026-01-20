#!/bin/bash
set -euo pipefail

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
TOPO_FILE=~/pool_topology
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

echo "INIT SCRIPT STARTING..."
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "NS_PATH: $NS_PATH"

# importing utility functions
source $NS_PATH/utils.sh

echo
echo '---------------- Reading pool topology file and preparing a few things... ----------------'

read ERROR NODE_TYPE BP_IP RELAYS < <(get_topo $TOPO_FILE)
RELAYS=($RELAYS)
cnt=${#RELAYS[@]}
let cnt1="$cnt/3"
let cnt2="$cnt1 + $cnt1"

RELAY_IPS=( "${RELAYS[@]:0:$cnt1}" )
RELAY_NAMES=( "${RELAYS[@]:$cnt1:$cnt1}" )
RELAY_IPS_PUB=( "${RELAYS[@]:$cnt2:$cnt1}" )

if [[ $ERROR == "none" ]]; then
    if [[ $NODE_TYPE == "" ]]; then
        echo "Node type not identified, something went wrong."
        echo "Please fix the underlying issue and run init.sh again."
        exit 1
    else
        echo "NODE_TYPE: $NODE_TYPE"
        echo "RELAY_IPS: ${RELAY_IPS[@]}"
        echo "RELAY_NAMES: ${RELAY_NAMES[@]}"
            echo "RELAY_IPS_PUB: ${RELAY_IPS_PUB[@]}"
    fi
else
    echo "ERROR: $ERROR"
    exit 1
fi

echo
echo '---------------- Keeping vm current with latest security updates ----------------'
sudo unattended-upgrade -d

echo
echo '---------------- Installing dependencies ----------------'
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
  automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev \
  libtinfo-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget \
  libncursesw5 libtool autoconf liblmdb-dev \
  bc tcptraceroute curl ca-certificates xz-utils \
  chrony


echo
echo '---------------- Tweaking chrony and sysctl configurations ----------------'
# backuping conf files
sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.$NOW
sudo cp /etc/sysctl.conf /etc/sysctl.conf.$NOW
# replacing conf files with our own version
sudo cp $SCRIPT_DIR/config/chrony.conf /etc/chrony/chrony.conf
sudo cp $SCRIPT_DIR/config/sysctl.conf /etc/sysctl.conf
sudo sysctl --system
sudo systemctl restart chrony


# echo '---------------- Setting up swap file  ----------------'
# todo
# as root, edit /etc/waagent.conf:
#ResourceDisk.Format=y
#ResourceDisk.EnableSwap=y
#ResourceDisk.SwapSizeMB=14336 for bp, 3072 for relay
#service walinuxagent restart
#check with swapon -s

# other important variables
DOWNLOAD_PATH="/home/cardano/download"
DOWNLOAD_PATH=$(prompt_input_default DOWNLOAD_PATH $DOWNLOAD_PATH)
mkdir -p "$DOWNLOAD_PATH"

CARDANO_NODE_INSTALL_PATH="/home/cardano"
CARDANO_NODE_INSTALL_PATH=$(prompt_input_default CARDANO_NODE_INSTALL_PATH "$CARDANO_NODE_INSTALL_PATH")
mkdir -p "$CARDANO_NODE_INSTALL_PATH"

# cardano-node version handling
CARDANO_NODE_TAG="${1:-}"
if [[ -z "$CARDANO_NODE_TAG" ]]; then
  CARDANO_NODE_TAG=$(curl -s https://api.github.com/repos/intersectmbo/cardano-node/releases/latest | jq -r .tag_name)
fi

if [[ $NODE_TYPE == "bp" ]]; then
    echo "Cardano node tag to build: $CARDANO_NODE_TAG"
    if ! promptyn "Proceed with building cardano-node $CARDANO_NODE_TAG ? (y/n)"; then exit 1; fi
fi

echo
echo '---------------- Installing Cabal & GHC dependency ----------------'
export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
export BOOTSTRAP_HASKELL_GHC_VERSION=8.10.7
export BOOTSTRAP_HASKELL_CABAL_VERSION=3.8.1.0
export BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1
export BOOTSTRAP_HASKELL_ADJUST_BASHRC=1

curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

export PATH="$HOME/.ghcup/bin:$HOME/.local/bin:$PATH"

# This is an interactive session make sure to start a new shell before resuming the rest of the install process below.

echo "Installing ghc 8.10.7"
ghcup install ghc 8.10.7
echo

echo "Installing cabal 3.8.1.0"
ghcup install cabal 3.8.1.0

ghcup set ghc 8.10.7
ghcup set cabal 3.8.1.0

echo "Make sure ghc and cabal points to .ghcup locations."
echo "If not you may have to add the below to your .bashrc:"
echo "   export PATH=/home/cardano/.ghcup/bin:\$PATH"
which cabal
which ghc
echo 

cabal --version
ghc --version

if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

echo
echo '---------------- Libsodium dependency ----------------'
ISLIBSODIUM=$(ldconfig -p | grep libsodium | wc -l)

if [[ $ISLIBSODIUM -eq 0 ]];then
    echo "libsodium lib not found, installing..."
    mkdir -p "$DOWNLOAD_PATH"
    cd "$DOWNLOAD_PATH"
    if [[ ! -d libsodium ]]; then
        git clone https://github.com/intersectmbo/libsodium
    fi
    cd libsodium
    git fetch --all --tags
    git reset --hard
    git clean -fdx
    git checkout dbb48cc
    ./autogen.sh
    ./configure
    make
    sudo make install
    sudo ldconfig
else
    echo "libsodium lib found, no installation required."
fi

echo '---------------- secp256k1 dependency ----------------'
ISSECP256K1=$(ldconfig -p | grep secp256k1 | wc -l)

if [[ $ISSECP256K1 -eq 0 ]];then
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
    # ./configure --prefix=/usr --enable-module-schnorrsig --enable-experimental
    ./configure --enable-module-schnorrsig --enable-experimental
    make
    make check
    sudo make install
    sudo ldconfig
else
    echo "secp256k1 lib found, no installation required."
fi

echo '---------------- BLST dependency ----------------'
if [[ ! -f /usr/local/lib/libblst.a ]]; then
    echo "libblst lib not found, installing..."
    mkdir -p "$DOWNLOAD_PATH"
    cd "$DOWNLOAD_PATH"
    if [[ ! -d blst ]]; then
        git clone https://github.com/supranational/blst
    fi
    cd blst
    git fetch --all --tags
    git reset --hard
    git clean -fdx
    git checkout v0.3.10
    ./build.sh
    cat > libblst.pc << EOF
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libblst
Description: Multilingual BLS12-381 signature library
URL: https://github.com/supranational/blst
Version: 0.3.10
Cflags: -I\${includedir}
Libs: -L\${libdir} -lblst
EOF
    sudo cp libblst.pc /usr/local/lib/pkgconfig/
    sudo cp bindings/blst_aux.h bindings/blst.h bindings/blst.hpp  /usr/local/include/
    sudo cp libblst.a /usr/local/lib
    sudo chmod u=rw,go=r /usr/local/{lib/{libblst.a,pkgconfig/libblst.pc},include/{blst.{h,hpp},blst_aux.h}}
else
    echo "libblst lib found, no installation required."
fi

# Add $HOME/.local/bin to $PATH and ~/.bashrc if required
echo "\$PATH Before: $PATH"
if [[ ! ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    echo "\$HOME/.local/bin not found in \$PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$PATH':" == *":'$HOME'/.local/bin:"* ]]; then
    export PATH=\$HOME/.local/bin:\$PATH
fi" >> ~/.bashrc
else
    echo "\$HOME/.local/bin found in \$PATH, nothing to change here."
fi
echo "\$PATH After: $PATH"

# Add /usr/local/lib to $LD_LIBRARY_PATH and ~/.bashrc if required
echo "\$LD_LIBRARY_PATH Before: $LD_LIBRARY_PATH"
if [[ ! ":$LD_LIBRARY_PATH:" == *":/usr/local/lib:"* ]]; then
    echo "/usr/local/lib not found in \$LD_LIBRARY_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$LD_LIBRARY_PATH':" == *":/usr/local/lib:"* ]]; then
    export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH
fi" >> ~/.bashrc
else
    echo "/usr/local/lib found in \$LD_LIBRARY_PATH, nothing to change here."
fi
echo "\$LD_LIBRARY_PATH After: $LD_LIBRARY_PATH"

# Add /usr/local/lib/pkgconfig to $PKG_CONFIG_PATH and ~/.bashrc if required
echo "\$PKG_CONFIG_PATH Before: $PKG_CONFIG_PATH"
if [[ ! ":$PKG_CONFIG_PATH:" == *":/usr/local/lib/pkgconfig:"* ]]; then
    echo "/usr/local/lib/pkgconfig not found in \$PKG_CONFIG_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$PKG_CONFIG_PATH':" == *":/usr/local/lib/pkgconfig:"* ]]; then
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:\$PKG_CONFIG_PATH
fi" >> ~/.bashrc
else
    echo "/usr/local/lib/pkgconfig found in \$PKG_CONFIG_PATH, nothing to change here."
fi
echo "\$PKG_CONFIG_PATH After: $PKG_CONFIG_PATH"

# building cardano binaries from bp node
if [[ $NODE_TYPE == "bp" ]]; then
    echo
    echo '---------------- Building the node from source ----------------'
    cd "$CARDANO_NODE_INSTALL_PATH"
    if [[ ! -d cardano-node ]]; then
        git clone https://github.com/intersectmbo/cardano-node.git
    fi

    if ! git rev-parse -q --verify "refs/tags/$CARDANO_NODE_TAG" >/dev/null; then
        echo "ERROR: tag $CARDANO_NODE_TAG not found in cardano-node repo"
        exit 1
    fi
    cd cardano-node
    git fetch --all --recurse-submodules --tags
    git reset --hard
    git clean -fdx
    git describe --tags --always || true
    git checkout "tags/$CARDANO_NODE_TAG"
    cabal configure --with-compiler="ghc-${BOOTSTRAP_HASKELL_GHC_VERSION}"
    echo -e "package cardano-crypto-praos\n  flags: -external-libsodium-vrf" > cabal.project.local
    cabal build all -j"$(nproc)"
    cp -p "$($NS_PATH/bin_path.sh cardano-cli)" ~/.local/bin/
    cp -p "$($NS_PATH/bin_path.sh cardano-node)" ~/.local/bin/
    cardano-cli --version
fi

echo "INIT_PART1 IS COMPLETED."

