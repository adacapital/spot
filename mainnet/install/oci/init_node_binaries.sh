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

# echo
# echo '---------------- Keeping vm current with latest security updates ----------------'
# sudo unattended-upgrade -d

# echo
# echo '---------------- Installing dependencies ----------------'
# sudo apt-get update -y
# sudo apt-get upgrade -y
# sudo apt-get install automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev libtinfo-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget libncursesw5 libtool autoconf liblmdb-dev libffi7 libgmp10 libncurses-dev libncurses5 libtinfo5 llvm-12 numactl libnuma-dev -y
# sudo apt-get install bc tcptraceroute curl -y
# sudo apt-get install firewalld
# sudo systemctl enable firewalld
# sudo systemctl start firewalld

# echo
# echo '---------------- Installing Chrony ----------------'
# sudo apt install chrony
# # backuping conf files
# sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.$NOW

# # replacing conf files with our own version
# sudo cp $CONF_PATH/chrony.conf /etc/chrony/chrony.conf
# sudo systemctl restart chrony

# echo
# echo '---------------- Cabal & GHC dependency ----------------'
# curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

# # This is an interactive session make sure to start a new shell before resuming the rest of the install process below.
# echo "Make sure ghc and cabal points to .ghcup locations."
# echo "If not you may have to add the below to your .bashrc:"
# echo "   export PATH=/home/cardano/.ghcup/bin:\$PATH"
# which cabal
# which ghc
# echo 

# echo "Installing ghc 8.10.7"
# ghcup install ghc 8.10.7
# echo

# echo "Installing cabal 3.8.1.0"
# ghcup install cabal 3.8.1.0

# ghcup set ghc 8.10.7
# ghcup set cabal 3.8.1.0

# cabal --version
# ghc --version

# if ! promptyn "Please confirm you want to proceed? (y/n)"; then
#     echo "Ok bye!"
#     exit 1
# fi

# echo
# echo '---------------- Libsodium dependency ----------------'
# ISLIBSODIUM=$(ldconfig -p | grep libsodium | wc -l)

# if [[ $ISLIBSODIUM -eq 1 ]] || [[ $ISLIBSODIUM -eq 0 ]]; then
#     echo "libsodium required, installing..."
#     mkdir -p $DOWNLOAD_PATH
#     cd $DOWNLOAD_PATH
#     git clone https://github.com/input-output-hk/libsodium
#     cd libsodium
#     git checkout dbb48cc
#     ./autogen.sh
#     ./configure
#     make
#     sudo make install
# else
#     echo "libsodium lib found, no installation required."
# fi

# echo '---------------- secp256k1 dependency ----------------'
# ISSECP256K1=$(ldconfig -p | grep secp256k1 | wc -l)

# if [[ $ISSECP256K1 -eq 0 ]];then
#     echo "secp256k1 lib not found, installing..."
#     mkdir -p $DOWNLOAD_PATH
#     cd $DOWNLOAD_PATH
#     git clone https://github.com/bitcoin-core/secp256k1.git
#     cd secp256k1
#     # git reset --hard ac83be33d0956faf6b7f61a60ab524ef7d6a473a
#     git checkout ac83be33
#     ./autogen.sh
#     # ./configure --prefix=/usr --enable-module-schnorrsig --enable-experimental
#     ./configure --enable-module-schnorrsig --enable-experimental
#     make
#     make check
#     sudo make install
# else
#     echo "secp256k1 lib found, no installation required."
# fi

# echo '---------------- BLST dependency ----------------'
# ISBLST=$(ldconfig -p | grep libblst | wc -l)

# if [[ $ISBLST -eq 0 ]];then
#     echo "libblst lib not found, installing..."
#     mkdir -p $DOWNLOAD_PATH
#     cd $DOWNLOAD_PATH

#     git clone https://github.com/supranational/blst
#     cd blst
#     git checkout v0.3.10
#     ./build.sh
#     cat > libblst.pc << EOF
# prefix=/usr/local
# exec_prefix=\${prefix}
# libdir=\${exec_prefix}/lib
# includedir=\${prefix}/include

# Name: libblst
# Description: Multilingual BLS12-381 signature library
# URL: https://github.com/supranational/blst
# Version: 0.3.10
# Cflags: -I\${includedir}
# Libs: -L\${libdir} -lblst
# EOF
#     sudo cp libblst.pc /usr/local/lib/pkgconfig/
#     sudo cp bindings/blst_aux.h bindings/blst.h bindings/blst.hpp  /usr/local/include/
#     sudo cp libblst.a /usr/local/lib
#     sudo chmod u=rw,go=r /usr/local/{lib/{libblst.a,pkgconfig/libblst.pc},include/{blst.{h,hpp},blst_aux.h}}

#     git clone https://github.com/bitcoin-core/secp256k1.git
#     cd secp256k1
#     git reset --hard ac83be33d0956faf6b7f61a60ab524ef7d6a473a
#     ./autogen.sh
#     ./configure --prefix=/usr --enable-module-schnorrsig --enable-experimental
#     make
#     make check
#     sudo make install
# else
#     echo "libblst lib found, no installation required."
# fi

# echo
# # Add /usr/local/lib to $LD_LIBRARY_PATH and ~/.bashrc if required
# echo "\$LD_LIBRARY_PATH Before: $LD_LIBRARY_PATH"
# if [[ ! ":$LD_LIBRARY_PATH:" == *":/usr/local/lib:"* ]]; then
#     echo "/usr/local/lib not found in \$LD_LIBRARY_PATH"
#     echo "Tweaking your .bashrc"
#     echo $"if [[ ! ":'$LD_LIBRARY_PATH':" == *":/usr/local/lib:"* ]]; then
#     export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH
# fi" >> ~/.bashrc
#     eval "$(cat ~/.bashrc | tail -n +10)"
# else
#     echo "/usr/local/lib found in \$LD_LIBRARY_PATH, nothing to change here."
# fi
# echo "\$LD_LIBRARY_PATH After: $LD_LIBRARY_PATH"

# echo
# # Add /usr/local/lib/pkgconfig to $PKG_CONFIG_PATH and ~/.bashrc if required
# echo "\$PKG_CONFIG_PATH Before: $PKG_CONFIG_PATH"
# if [[ ! ":$PKG_CONFIG_PATH:" == *":/usr/local/lib/pkgconfig:"* ]]; then
#     echo "/usr/local/lib/pkgconfig not found in \$PKG_CONFIG_PATH"
#     echo "Tweaking your .bashrc"
#     echo $"if [[ ! ":'$PKG_CONFIG_PATH':" == *":/usr/local/lib/pkgconfig:"* ]]; then
#     export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:\$PKG_CONFIG_PATH
# fi" >> ~/.bashrc
#     eval "$(cat ~/.bashrc | tail -n +10)"
# else
#     echo "/usr/local/lib/pkgconfig found in \$PKG_CONFIG_PATH, nothing to change here."
# fi
# echo "\$PKG_CONFIG_PATH After: $PKG_CONFIG_PATH"

# mkdir -p ~/.local/bin
# echo
# # Add $HOME/.local/bin to $PATH and ~/.bashrc if required
# echo "\$PATH Before: $PATH"
# if [[ ! ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
#     echo "\$HOME/.local/bin not found in \$PATH"
#     echo "Tweaking your .bashrc"
#     echo $"if [[ ! ":'$PATH':" == *":'$HOME'/.local/bin:"* ]]; then
#     export PATH=\$HOME/.local/bin:\$PATH
# fi" >> ~/.bashrc
#     eval "$(cat ~/.bashrc | tail -n +10)"
# else
#     echo "\$HOME/.local/bin found in \$PATH, nothing to change here."
# fi
# echo "\$PATH After: $PATH"

echo
echo '---------------- Building cardano-node with cabal ----------------'
INSTALL_PATH=$HOME/data
INSTALL_PATH=$(prompt_input_default INSTALL_PATH $INSTALL_PATH)

LATESTTAG=$(curl -s https://api.github.com/repos/input-output-hk/cardano-node/releases/latest | jq -r .tag_name)
LATESTTAG=$(prompt_input_default CHECKOUT_TAG $LATESTTAG)

echo
echo "Details of your cardano-node build:"
echo "INSTALL_PATH: $INSTALL_PATH"
echo "LATESTTAG: $LATESTTAG"
if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

echo
echo "Getting the source code.."
mkdir -p $INSTALL_PATH
cd $INSTALL_PATH
git clone https://github.com/input-output-hk/cardano-node.git
cd cardano-node

git fetch --all --recurse-submodules --tags
# git checkout $LATESTTAG
git checkout tags/$LATESTTAG

echo "with-compiler: ghc-8.10.7" >> cabal.project.local

echo
git describe --tags

echo
if ! promptyn "Is this the correct tag? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

# cabal configure -O0 -w ghc-8.10.7

# echo -e "package cardano-crypto-praos\n flags: -external-libsodium-vrf" > cabal.project.local
# sed -i $HOME/.cabal/config -e "s/overwrite-policy:/overwrite-policy: always/g"
# rm -rf dist-newstyle/build/aarch64-linux/ghc-8.10.7

# echo "with-compiler: ghc-8.10.7" >> cabal.project.local
# echo -e "package cardano-crypto-praos\n  flags: -external-libsodium-vrf" >> cabal.project.local

cabal update
# cabal build all 2>&1 | tee /tmp/build.cardano-node.log
# cabal build cardano-cli cardano-node cardano-submit-api bech32
cabal build all

cp -p "$($ROOT_DIR/scripts/bin_path.sh cardano-cli $INSTALL_PATH/cardano-node)" ~/.local/bin/
cp -p "$($ROOT_DIR/scripts/bin_path.sh cardano-node $INSTALL_PATH/cardano-node)" ~/.local/bin/

echo
cardano-cli --version
cardano-node --version