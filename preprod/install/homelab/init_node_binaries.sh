#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
BASE_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
ROOT_DIR="$(realpath "$(dirname "$BASE_DIR")")"
CONF_PATH="$BASE_DIR/config"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "BASE_DIR: $BASE_DIR"
echo "ROOT_DIR: $ROOT_DIR"
echo "CONF_PATH: $CONF_PATH"
echo

# importing utility functions
source $ROOT_DIR/scripts/utils.sh

# other important variables
DOWNLOAD_PATH="/home/cardano/data/download"
DOWNLOAD_PATH=$(prompt_input_default DOWNLOAD_PATH $DOWNLOAD_PATH)

echo
echo "Details of your installation:"
echo "DOWNLOAD_PATH: $DOWNLOAD_PATH"
if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

echo "CARDANO-NODE-INIT STARTING..."

echo
echo '---------------- Keeping vm current with latest security updates ----------------'
sudo unattended-upgrade -d

echo
echo '---------------- Installing dependencies ----------------'
sudo apt-get update -y
sudo apt-get upgrade -y
# Per IOG: https://developers.cardano.org/docs/get-started/infrastructure/node/installing-cardano-node/
sudo apt-get install -y automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev libncurses-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget libtool autoconf liblmdb-dev libsnappy-dev protobuf-compiler liburing-dev
sudo apt-get install -y bc tcptraceroute curl
sudo apt-get install -y firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld

echo
echo '---------------- Installing Chrony ----------------'
sudo apt install chrony
# backuping conf files
sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.$NOW

# replacing conf files with our own version
sudo cp $CONF_PATH/chrony.conf /etc/chrony/chrony.conf
sudo systemctl restart chrony

echo
echo '---------------- Resolving versions from iohk-nix (single source of truth) ----------------'
# Prompt for cardano-node tag once, then derive all pinned C-lib versions from iohk-nix flake.lock.
# This is the same cascade documented at:
#   https://developers.cardano.org/docs/get-started/infrastructure/node/installing-cardano-node/
LATESTTAG=$(curl -s https://api.github.com/repos/intersectmbo/cardano-node/releases/latest | jq -r .tag_name)
LATESTTAG=$(prompt_input_default CARDANO_NODE_TAG $LATESTTAG)

IOHKNIX_VERSION=$(curl -s https://raw.githubusercontent.com/IntersectMBO/cardano-node/$LATESTTAG/flake.lock | jq -r '.nodes.iohkNix.locked.rev')
SODIUM_VERSION=$(curl -s https://raw.githubusercontent.com/input-output-hk/iohk-nix/$IOHKNIX_VERSION/flake.lock | jq -r '.nodes.sodium.original.rev')
SECP256K1_VERSION=$(curl -s https://raw.githubusercontent.com/input-output-hk/iohk-nix/$IOHKNIX_VERSION/flake.lock | jq -r '.nodes.secp256k1.original.ref')
BLST_VERSION=$(curl -s https://raw.githubusercontent.com/input-output-hk/iohk-nix/$IOHKNIX_VERSION/flake.lock | jq -r '.nodes.blst.original.ref')

echo "CARDANO_NODE_TAG:  $LATESTTAG"
echo "IOHKNIX_VERSION:   $IOHKNIX_VERSION"
echo "SODIUM_VERSION:    $SODIUM_VERSION"
echo "SECP256K1_VERSION: $SECP256K1_VERSION"
echo "BLST_VERSION:      $BLST_VERSION"

if ! promptyn "Versions resolved. Proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

echo
echo '---------------- Cabal & GHC dependency ----------------'
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

# This is an interactive session make sure to start a new shell before resuming the rest of the install process below.

# Per IOG docs (re-check on each upgrade):
ghcup install ghc 9.6.7 --set
ghcup install cabal 3.12.1.0 --set

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
    mkdir -p $DOWNLOAD_PATH
    cd $DOWNLOAD_PATH
    git clone https://github.com/intersectmbo/libsodium
    cd libsodium
    git checkout "$SODIUM_VERSION"
    ./autogen.sh
    ./configure
    make
    sudo make install
else
    echo "libsodium lib found, no installation required."
fi

echo '---------------- secp256k1 dependency ----------------'
ISSECP256K1=$(ldconfig -p | grep secp256k1 | wc -l)

if [[ $ISSECP256K1 -eq 0 ]];then
    echo "secp256k1 lib not found, installing..."
    mkdir -p $DOWNLOAD_PATH
    cd $DOWNLOAD_PATH
    git clone https://github.com/bitcoin-core/secp256k1.git
    cd secp256k1
    git fetch --all --tags
    git checkout "$SECP256K1_VERSION"
    ./autogen.sh
    ./configure --enable-module-schnorrsig --enable-experimental
    make
    make check
    sudo make install
else
    echo "secp256k1 lib found, no installation required."
fi

echo '---------------- BLST dependency ----------------'
ISBLST=$(ldconfig -p | grep libblst | wc -l)

if [[ $ISBLST -eq 0 ]];then
    echo "libblst lib not found, installing..."
    mkdir -p $DOWNLOAD_PATH
    cd $DOWNLOAD_PATH

    git clone https://github.com/supranational/blst
    cd blst
    git fetch --all --tags
    git checkout "$BLST_VERSION"
    ./build.sh
    BLST_PC_VERSION="${BLST_VERSION#v}"
    cat > libblst.pc << EOF
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
    sudo cp bindings/blst_aux.h bindings/blst.h bindings/blst.hpp  /usr/local/include/
    sudo cp libblst.a /usr/local/lib
    sudo chmod u=rw,go=r /usr/local/{lib/{libblst.a,pkgconfig/libblst.pc},include/{blst.{h,hpp},blst_aux.h}}
else
    echo "libblst lib found, no installation required."
fi

echo
# Add /usr/local/lib to $LD_LIBRARY_PATH and ~/.bashrc if required
echo "\$LD_LIBRARY_PATH Before: $LD_LIBRARY_PATH"
if [[ ! ":$LD_LIBRARY_PATH:" == *":/usr/local/lib:"* ]]; then
    echo "/usr/local/lib not found in \$LD_LIBRARY_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$LD_LIBRARY_PATH':" == *":/usr/local/lib:"* ]]; then
    export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH
fi" >> ~/.bashrc
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "/usr/local/lib found in \$LD_LIBRARY_PATH, nothing to change here."
fi
echo "\$LD_LIBRARY_PATH After: $LD_LIBRARY_PATH"

echo
# Add /usr/local/lib/pkgconfig to $PKG_CONFIG_PATH and ~/.bashrc if required
echo "\$PKG_CONFIG_PATH Before: $PKG_CONFIG_PATH"
if [[ ! ":$PKG_CONFIG_PATH:" == *":/usr/local/lib/pkgconfig:"* ]]; then
    echo "/usr/local/lib/pkgconfig not found in \$PKG_CONFIG_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$PKG_CONFIG_PATH':" == *":/usr/local/lib/pkgconfig:"* ]]; then
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:\$PKG_CONFIG_PATH
fi" >> ~/.bashrc
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "/usr/local/lib/pkgconfig found in \$PKG_CONFIG_PATH, nothing to change here."
fi
echo "\$PKG_CONFIG_PATH After: $PKG_CONFIG_PATH"

mkdir -p ~/.local/bin
echo
# Add $HOME/.local/bin to $PATH and ~/.bashrc if required
echo "\$PATH Before: $PATH"
if [[ ! ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    echo "\$HOME/.local/bin not found in \$PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$PATH':" == *":'$HOME'/.local/bin:"* ]]; then
    export PATH=\$HOME/.local/bin:\$PATH
fi" >> ~/.bashrc
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "\$HOME/.local/bin found in \$PATH, nothing to change here."
fi
echo "\$PATH After: $PATH"

echo
echo '---------------- Building cardano-node with cabal ----------------'
INSTALL_PATH=$HOME/data
INSTALL_PATH=$(prompt_input_default INSTALL_PATH $INSTALL_PATH)

echo
echo "Details of your cardano-node build:"
echo "INSTALL_PATH: $INSTALL_PATH"
echo "CARDANO_NODE_TAG: $LATESTTAG"
if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

echo
echo "Getting the source code.."
mkdir -p $INSTALL_PATH
cd $INSTALL_PATH
git clone https://github.com/intersectmbo/cardano-node.git
cd cardano-node

git fetch --all --recurse-submodules --tags
git checkout tags/$LATESTTAG

echo "with-compiler: ghc-9.6.7" >> cabal.project.local

echo
git describe --tags

echo
if ! promptyn "Is this the correct tag? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

cabal update
cabal build all

cp -p "$($ROOT_DIR/scripts/bin_path.sh cardano-cli $INSTALL_PATH/cardano-node)" ~/.local/bin/
cp -p "$($ROOT_DIR/scripts/bin_path.sh cardano-node $INSTALL_PATH/cardano-node)" ~/.local/bin/

echo
cardano-cli --version
cardano-node --version