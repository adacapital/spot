#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

echo "INIT SCRIPT STARTING..."
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "NS_PATH: $NS_PATH"

echo
echo '---------------- Keeping vm current with latest security updates ----------------'
sudo unattended-upgrade -d

echo
echo '---------------- Installing dependencies ----------------'
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev libtinfo-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget libncursesw5 libtool autoconf -y

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

echo
echo '---------------- Installing Cabal ----------------'
# Download most recent version (check this is still the right version here: https://www.haskell.org/cabal/download.html)
mkdir -p ~/download/cabal
cd ~/download/cabal
wget https://downloads.haskell.org/~cabal/cabal-install-3.4.0.0/cabal-install-3.4.0.0-x86_64-ubuntu-16.04.tar.xz
tar -xf cabal-install-3.4.0.0-x86_64-ubuntu-16.04.tar.xz
mkdir -p ~/.local/bin
cp cabal ~/.local/bin/

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

echo "Starting: cabal update"
~/.local/bin/cabal update
~/.local/bin/cabal user-config update
sed -i 's/overwrite-policy:/overwrite-policy: always/g' ~/.cabal/config
cabal --version
echo "Completed: cabal update"

echo
echo '---------------- Installing GHC ----------------'
# Download most recent version (check this is still the right version here: https://www.haskell.org/ghc/download.html)
mkdir -p ~/download/ghc
cd ~/download/ghc
wget https://downloads.haskell.org/~ghc/8.10.4/ghc-8.10.4-x86_64-deb9-linux.tar.xz 
tar -xf ghc-8.10.4-x86_64-deb9-linux.tar.xz 
cd ghc-8.10.4
./configure
sudo make install
ghc --version

echo
echo '---------------- Installing Libsodium ----------------'
cd ~/download/
git clone https://github.com/input-output-hk/libsodium
cd libsodium
git checkout 66f017f1
./autogen.sh
./configure
make
sudo make install

echo
echo '---------------- secp256k1 dependency ----------------'
cd ~/download
git clone https://github.com/bitcoin-core/secp256k1.git
cd secp256k1
git reset --hard ac83be33d0956faf6b7f61a60ab524ef7d6a473a
./autogen.sh
./configure --prefix=/usr --enable-module-schnorrsig --enable-experimental
make
make check
sudo make install

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

echo
echo '---------------- Building the node from source ----------------'
cd ~/download
git clone https://github.com/input-output-hk/cardano-node.git
cd cardano-node
git fetch --all --recurse-submodules --tags
git tag
LATEST_TAG=$(curl -s https://api.github.com/repos/input-output-hk/cardano-node/releases/latest | jq -r .tag_name)
git checkout tags/$LATEST_TAG
cabal configure --with-compiler=ghc-8.10.4
echo -e "package cardano-crypto-praos\n  flags: -external-libsodium-vrf" > cabal.project.local
~/.local/bin/cabal build all
cp -p "$($NS_PATH/bin_path.sh cardano-cli)" ~/.local/bin/
cp -p "$($NS_PATH/bin_path.sh cardano-node)" ~/.local/bin/
cardano-cli --version

echo
echo '---------------- Preparing topology, genesis and config files ----------------'
mkdir -p ~/node.relay/config
mkdir -p ~/node.relay/socket
mkdir -p ~/node.relay/logs
mkdir -p ~/node.bp/config
mkdir -p ~/node.bp/socket
mkdir -p ~/node.bp/logs
cd ~/node.relay/config
wget -O config.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-config.json
wget -O bgenesis.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-byron-genesis.json
wget -O sgenesis.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-shelley-genesis.json
wget -O agenesis.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-alonzo-genesis.json
wget -O topology.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-topology.json
sed -i 's/"TraceBlockFetchDecisions": false/"TraceBlockFetchDecisions": true/g' config.json
sed -i 's/testnet-byron-genesis/bgenesis/g' config.json
sed -i 's/testnet-shelley-genesis/sgenesis/g' config.json
cp ./* ~/node.bp/config
# todo upgrade sed commands to match target config currently set in node.relay and node.bp folders

# setting up important environment variables

echo "\$CARDANO_NODE_SOCKET_PATH Before: $CARDANO_NODE_SOCKET_PATH"
if [[ ! ":$CARDANO_NODE_SOCKET_PATH:" == *":$HOME/node.relay/socket:"* ]]; then
    echo "\$HOME/node.relay/socket not found in \$CARDANO_NODE_SOCKET_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$CARDANO_NODE_SOCKET_PATH':" == *":'$HOME'/node.relay/socket:"* ]]; then
    export CARDANO_NODE_SOCKET_PATH=\$HOME/node.relay/socket
fi" >> ~/.bashrc
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "\$HOME/node.relay/socket found in \$CARDANO_NODE_SOCKET_PATH, nothing to change here."
fi
echo "\$CARDANO_NODE_SOCKET_PATH After: $CARDANO_NODE_SOCKET_PATH"

if [[ ! ":$SPOT_PATH:" == *":$SPOT_DIR:"* ]]; then
    echo "\$SPOT_DIR not found in \$SPOT_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$SPOT_PATH':" == *":$SPOT_DIR:"* ]]; then
    export SPOT_PATH=$SPOT_DIR
fi" >> ~/.bashrc
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "\$SPOT_DIR found in \$SPOT_PATH, nothing to change here."
fi
echo "\$SPOT_PATH After: $SPOT_PATH"

echo "INIT SCRIPT COMPLETED."

