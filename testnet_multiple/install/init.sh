#!/bin/bash
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

echo
echo '---------------- Reading pool topology file and preparing a few things... ----------------'
MY_IP=$(hostname -I | xargs)
NODE_TYPE=""
RELAY_IPS=()
RELAY_NAMES=()
echo "MY_IP: ${MY_IP}"

if [[ -f "$TOPO_FILE" ]]; then
    echo "Working on topo file..."
    while IFS= read -r TOPO; do
        echo $TOPO
        if [[ ! -z $TOPO ]]; then
            TOPO_IP=$(awk '{ print $1 }' <<< "${TOPO}")
            TOPO_NAME=$(awk '{ print $2 }' <<< "${TOPO}")
            #echo "TOPO_IP: ${TOPO_IP}"
            #echo "TOPO_NAME: ${TOPO_NAME}"
            if [[ $TOPO_IP == $MY_IP ]]; then
                if [[ "$TOPO_NAME" == *"bp"* ]]; then
                    NODE_TYPE="bp"
                elif [[ "$TOPO_NAME" == *"relay"* ]]; then
                    NODE_TYPE="relay"
                fi
            else
                if [[ "$TOPO_NAME" == *"relay"* ]]; then
                    RELAY_IPS+=($TOPO_IP)
                    RELAY_NAMES+=($TOPO_NAME)
                fi
            fi
        fi
    done <$TOPO_FILE

    echo "NODE_TYPE: $NODE_TYPE"
    echo "RELAY_IPS: ${RELAY_IPS[@]}"
    echo "RELAY_NAMES: ${RELAY_NAMES[@]}"
else 
    echo "$TOPO_FILE does not exist. Please create it as per instructions and run this script again."
    exit 1
fi

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

# todo add sshd tweaks

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

if [[ $NODE_TYPE == "bp" ]]; then
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
fi

echo
echo '---------------- Preparing topology, genesis and config files ----------------'
NODE_DIR="node.bp"
if [[ $NODE_TYPE == "relay" ]]; then
    NODE_DIR="node.relay"
fi

mkdir -p ~/$NODE_DIR/config
mkdir -p ~/$NODE_DIR/socket
mkdir -p ~/$NODE_DIR/logs
cd ~/$NODE_DIR/config
wget -O config.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-config.json
wget -O bgenesis.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-byron-genesis.json
wget -O sgenesis.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-shelley-genesis.json
wget -O topology.json https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-topology.json
sed -i 's/"TraceBlockFetchDecisions": false/"TraceBlockFetchDecisions": true/g' config.json
sed -i 's/testnet-byron-genesis/bgenesis/g' config.json
sed -i 's/testnet-shelley-genesis/sgenesis/g' config.json

# todo upgrade sed commands to match target config currently set in node.relay and node.bp folders

# setting up important environment variables

echo "\$CARDANO_NODE_SOCKET_PATH Before: $CARDANO_NODE_SOCKET_PATH"
if [[ ! ":$CARDANO_NODE_SOCKET_PATH:" == *":$HOME/$NODE_DIR/socket:"* ]]; then
    echo "\$HOME/$NODE_DIR/socket not found in \$CARDANO_NODE_SOCKET_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$CARDANO_NODE_SOCKET_PATH':" == *":'$HOME'/$NODE_DIR/socket:"* ]]; then
    export CARDANO_NODE_SOCKET_PATH=\$HOME/$NODE_DIR/socket
fi" >> ~/.bashrc
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "\$HOME/$NODE_DIR/socket found in \$CARDANO_NODE_SOCKET_PATH, nothing to change here."
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

if [[ $NODE_TYPE == "bp" ]]; then
    echo
    echo '---------------- Getting other peers ready... ----------------'

    RELAYS_COUNT=${#RELAY_IPS[@]}

    for (( i=0; i<${RELAYS_COUNT}; i++ ));
    do
        echo "Checking ${RELAY_IPS[$i]} is online..."
        ping -c1 -W1 -q ${RELAY_IPS[$i]} &>/dev/null
        status=$( echo $? )
        if [[ $status == 0 ]] ; then
            echo "Online"
            echo '---------------- Copying pool_topology file... ----------------'
            scp -i ~/.ssh/${RELAY_NAMES[$i]}.pem ~/pool_topology cardano@${RELAY_IPS[$i]}:/home/cardano
            echo '---------------- Copying cardano binaries... ----------------'
            ssh -i ~/.ssh/${RELAY_NAMES[$i]}.pem cardano@${RELAY_IPS[$i]} 'mkdir -p ~/.local/bin'
            scp -i ~/.ssh/${RELAY_NAMES[$i]}.pem ~/.local/bin/cardano* cardano@${RELAY_IPS[$i]}:/home/cardano/.local/bin
        else
            echo "Offline"
        fi
    done
fi

echo "INIT SCRIPT COMPLETED."

