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

# importing utility functions
source $NS_PATH/utils.sh

# todo, manage air-gapped machine which should only run dependencies installation and exit!

echo
echo '---------------- Reading pool topology file and preparing a few things... ----------------'

read ERROR NODE_TYPE BP_IP RELAYS < <(get_topo $TOPO_FILE)
RELAYS=($RELAYS)
cnt=${#RELAYS[@]}
let cnt1="$cnt/3"
let cnt2="$cnt1 + $cnt1"
let cnt3="$cnt2 + $cnt1"

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
sudo apt-get install automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev libtinfo-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget libncursesw5 libtool autoconf liblmdb-dev libffi7 libgmp10 libncurses-dev libncurses5 libtinfo5 -y
sudo apt-get install bc tcptraceroute curl -y

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
echo '---------------- Hardening the vm  ----------------'

# tweaking sshd config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bkp
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
sudo sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/g' /etc/ssh/sshd_config
# check new sshd config is correct
sudo sshd -t 2>sshd.err
if [[ -s sshd.err ]]; then
    echo
    echo "Warning, /etc/ssh/sshd_config is not correct:"
    cat sshd.err
    exit 1
else
    sudo rm -f sshd.err
    echo "restarting sshd service"
    sudo service sshd reload
fi

echo
echo '---------------- Setting up swap file  ----------------'
# todo
# as root, edit /etc/waagent.conf:
#ResourceDisk.Format=y
#ResourceDisk.EnableSwap=y
#ResourceDisk.SwapSizeMB=14336 for bp, 3072 for relay
#service walinuxagent restart
#check with swapon -s

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
git checkout dbb48cc
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

# building cardano binaries from bp node
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
wget -O config.json https://book.world.dev.cardano.org/environments/mainnet/config-bp.json
wget -O bgenesis.json https://book.world.dev.cardano.org/environments/mainnet/byron-genesis.json
wget -O sgenesis.json https://book.world.dev.cardano.org/environments/mainnet/shelley-genesis.json
wget -O agenesis.json https://book.world.dev.cardano.org/environments/mainnet/alonzo-genesis.json
wget -O topology.json https://book.world.dev.cardano.org/environments/mainnet/topology.json
wget -O cgenesis.json https://book.world.dev.cardano.org/environments/mainnet/conway-genesis.json

# prepare config.json

LINENO_SOURCE=$(grep -in defaultBackends config.json | awk -F: '{print $1}')
LINENO_TEMPLATE=$(grep -in defaultBackends $HOME/spot/mainnet/install/config/config_template.json | awk -F: '{print $1}')

head -$(expr $LINENO_SOURCE - 1) config.json > config.json.tmp
tail +$LINENO_TEMPLATE $HOME/spot/mainnet/install/config/config_template.json >> config.json.tmp

sed -i 's/"TraceBlockFetchClient": false,/"MaxConcurrencyDeadline": 4,\n\  "TraceBlockFetchClient": false,/g' config.json.tmp

sed -i 's/"TraceBlockFetchClient": true,/"TraceBlockFetchClient": false,/g' config.json.tmp
sed -i 's/"TraceBlockFetchDecisions": true,/"TraceBlockFetchDecisions": false,/g' config.json.tmp
sed -i 's/"TraceBlockFetchProtocol": true,/"TraceBlockFetchProtocol": false,/g' config.json.tmp
sed -i 's/"TraceBlockFetchProtocolSerialised": true,/"TraceBlockFetchProtocolSerialised": false,/g' config.json.tmp
sed -i 's/"TraceBlockFetchServer": true,/"TraceBlockFetchServer": false,/g' config.json.tmp
sed -i 's/"TraceChainDb": true,/"TraceChainDb": true,/g' config.json.tmp
sed -i 's/"TraceChainSyncBlockServer": true,/"TraceChainSyncBlockServer": false,/g' config.json.tmp
sed -i 's/"TraceChainSyncClient": true,/"TraceChainSyncClient": false,/g' config.json.tmp
sed -i 's/"TraceChainSyncHeaderServer": true,/"TraceChainSyncHeaderServer": false,/g' config.json.tmp
sed -i 's/"TraceChainSyncProtocol": true,/"TraceChainSyncProtocol": false,/g' config.json.tmp
sed -i 's/"TraceConnectionManager": true,/"TraceConnectionManager": false,/g' config.json.tmp
sed -i 's/"TraceDNSResolver": true,/"TraceDNSResolver": false,/g' config.json.tmp
sed -i 's/"TraceDNSSubscription": true,/"TraceDNSSubscription": false,/g' config.json.tmp
sed -i 's/"TraceDiffusionInitialization": true,/"TraceDiffusionInitialization": false,/g' config.json.tmp
sed -i 's/"TraceErrorPolicy": true,/"TraceErrorPolicy": false,/g' config.json.tmp
sed -i 's/"TraceForge": true,/"TraceForge": true,/g' config.json.tmp
sed -i 's/"TraceHandshake": true,/"TraceHandshake": false,/g' config.json.tmp
sed -i 's/"TraceInboundGovernor": true,/"TraceInboundGovernor": false,/g' config.json.tmp
sed -i 's/"TraceIpSubscription": true,/"TraceIpSubscription": false,/g' config.json.tmp
sed -i 's/"TraceLedgerPeers": true,/"TraceLedgerPeers": false,/g' config.json.tmp
sed -i 's/"TraceLocalChainSyncProtocol": true,/"TraceLocalChainSyncProtocol": false,/g' config.json.tmp
sed -i 's/"TraceLocalErrorPolicy": true,/"TraceLocalErrorPolicy": false,/g' config.json.tmp
sed -i 's/"TraceLocalHandshake": false,/"TraceLocalHandshake": false,/g' config.json.tmp
sed -i 's/"TraceLocalRootPeers": true,/"TraceLocalRootPeers": false,/g' config.json.tmp
sed -i 's/"TraceLocalTxSubmissionProtocol": true,/"TraceLocalTxSubmissionProtocol": false,/g' config.json.tmp
sed -i 's/"TraceLocalTxSubmissionServer": true,/"TraceLocalTxSubmissionServer": false,/g' config.json.tmp
sed -i 's/"TraceMempool": true,/"TraceMempool": true,/g' config.json.tmp
sed -i 's/"TraceMux": false,/"TraceMux": false,/g' config.json.tmp
sed -i 's/"TracePeerSelection": true,/"TracePeerSelection": false,/g' config.json.tmp
sed -i 's/"TracePeerSelectionActions": true,/"TracePeerSelectionActions": false,/g' config.json.tmp
sed -i 's/"TracePublicRootPeers": true,/"TracePublicRootPeers": false,/g' config.json.tmp
sed -i 's/"TraceServer": true,/"TraceServer": false,/g' config.json.tmp
sed -i 's/"TraceTxInbound": false,/"TraceTxInbound": true,/g' config.json.tmp
sed -i 's/"TraceTxOutbound": false,/"TraceTxOutbound": true,/g' config.json.tmp
sed -i 's/"TraceTxSubmissionProtocol": false,/"TraceTxSubmissionProtocol": true,/g' config.json.tmp
sed -i 's/"TracingVerbosity": "NormalVerbosity",/"TracingVerbosity": "NormalVerbosity",/g' config.json.tmp
sed -i 's/"TurnOnLogMetrics": true,/"TurnOnLogMetrics": true,/g' config.json.tmp
sed -i 's/"TurnOnLogging": true,/"TurnOnLogging": true,/g' config.json.tmp

sed -i 's/mainnet-byron-genesis/bgenesis/g' config.json.tmp
sed -i 's/mainnet-shelley-genesis/sgenesis/g' config.json.tmp
sed -i 's/mainnet-alonzo-genesis/agenesis/g' config.json.tmp

if [[ $NODE_TYPE == "bp" ]]; then
    sed -i 's/node.relay/node.bp/g' config.json.tmp
    sed -i 's/"hasEKG": 12788/"hasEKG": 12789/g' config.json.tmp
    sed -i 's/12798/12799/g' config.json.tmp
fi

mv config.json.tmp config.json

# todo upgrade sed commands to match target config.jsonb currently set in node.relay and node.bp folders

# building topology.json
if [[ $NODE_TYPE == "bp" ]]; then
    RELAYS_COUNT=${#RELAY_IPS[@]}
    RELAYS_JSON=$HOME/$NODE_DIR/config/relays.json

    for (( i=0; i<${RELAYS_COUNT}; i++ ));
    do
        echo -e "{\n \"addr\": \"${RELAY_IPS[$i]}\",\n \"port\": 3001,\n \"valency\": 1\n}," >> $RELAYS_JSON
    done

    echo -e "{ \n\"Producers\": [\n$(cat $RELAYS_JSON | head -n -1)} ]}" | jq . > $HOME/$NODE_DIR/config/topology.json

    rm -f $RELAYS_JSON
elif [[ $NODE_TYPE == "relay" ]]; then
    cp $HOME/$NODE_DIR/config/topology.json $HOME/$NODE_DIR/config/topology.json.bak
    JSON=$HOME/$NODE_DIR/config/topology.json.bak
    TMP_JSON=$HOME/$NODE_DIR/config/tmp.json

    # adding reference to bp node
    echo -e "{\n \"addr\": \"$BP_IP\",\n \"port\": 3000,\n \"valency\": 1\n}," >> $TMP_JSON

    # adding references to default iohk relays listed in the default iohk topology file
    cat $JSON | jq .Producers | jq -M -r '.[] | .addr, .port, .valency' | while read -r ADDR; read -r PORT; read -r VALENCY; do
        echo -e "{\n \"addr\": \"$ADDR\",\n \"port\": $PORT,\n \"valency\": $VALENCY\n}," >> $TMP_JSON
    done

    echo -e "{ \n\"Producers\": [\n$(cat $TMP_JSON | head -n -1)} ]}" | jq . > $HOME/$NODE_DIR/config/topology.json

    rm -f $JSON $TMP_JSON
fi

# setting up important environment variables

echo "\$CARDANO_NODE_SOCKET_PATH Before: $CARDANO_NODE_SOCKET_PATH"
if [[ ! ":$CARDANO_NODE_SOCKET_PATH:" == *":$HOME/$NODE_DIR/socket:"* ]]; then
    echo "\$HOME/$NODE_DIR/socket not found in \$CARDANO_NODE_SOCKET_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$CARDANO_NODE_SOCKET_PATH':" == *":'$HOME'/$NODE_DIR/socket:"* ]]; then
    export CARDANO_NODE_SOCKET_PATH=\$HOME/$NODE_DIR/socket/node.socket
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

# copying cardano binaries to relay nodes and other important files
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

# preparing the node starting script
if [[ $NODE_TYPE == "relay" ]]; then
    cp $SPOT_PATH/install/run.relay.sh $HOME/node.relay
elif [[ $NODE_TYPE == "bp" ]]; then
    # the bp node starting script is identical to a relay to start with, it will be customized later on once the pool gets registered
    cp $SPOT_PATH/install/run.relay.sh $HOME/node.bp/run.bp.sh
    sed -i 's/node.relay/node.bp/g' $HOME/node.bp/run.bp.sh
    sed -i 's/port 3001/port 3000/g' $HOME/node.bp/run.bp.sh
fi

# getting all node's socket db ready
echo "Please now start ${RELAY_NAMES[0]} (${RELAY_IPS[0]}) and wait until it is fully synchronized."
echo

if [[ $NODE_TYPE == "bp" ]]; then
    NEXT_STEP_OK=0
    while [ "$NEXT_STEP_OK" -eq 0 ]; do
        if ! promptyn "Please confirm ${RELAY_NAMES[0]} (${RELAY_IPS[0]}) is fully synchronized and stopped? (y/n)"; then
            echo "Ok let's wait some more"
        else
            NEXT_STEP_OK=1
        fi
    done

    # tar socket db on the synchronized relay
    echo "Preparing a tar file of socket db..."
    ssh -i ~/.ssh/${RELAY_NAMES[0]}.pem cardano@${RELAY_IPS[0]} 'tar -czvf /home/cardano/node.relay/relay.db.tar.gz -C /home/cardano/node.relay db'
    echo "Preparing the bp node's socket db..."
    scp -i ~/.ssh/${RELAY_NAMES[0]}.pem cardano@${RELAY_IPS[0]}:/home/cardano/node.relay/relay.db.tar.gz $HOME/node.bp

    # copy & untar socket db tar file to all relay nodes
    RELAYS_COUNT=${#RELAY_IPS[@]}

    for (( i=1; i<${RELAYS_COUNT}; i++ ));
    do
        echo "Copying socket db to ${RELAY_NAMES[i]} (${RELAY_IPS[i]})..."
        scp -i ~/.ssh/${RELAY_NAMES[i]}.pem $HOME/node.bp/relay.db.tar.gz cardano@${RELAY_IPS[i]}:/home/cardano/node.relay
        echo "Getting socket db ready for ${RELAY_NAMES[i]} (${RELAY_IPS[i]})..."
        ssh -i ~/.ssh/${RELAY_NAMES[i]}.pem cardano@${RELAY_IPS[i]} 'tar -xzvf /home/cardano/node.relay/relay.db.tar.gz -C /home/cardano/node.relay'  
    done

    # untar socket db tar file on bp node
    echo "Getting socket db ready for the bp node..."
    tar -xzvf /home/cardano/node.bp/relay.db.tar.gz -C /home/cardano/node.bp
fi

echo
echo '---------------- Getting our node systemd services ready ----------------'

if [[ $NODE_TYPE == "relay" ]]; then
    cat > $HOME/node.relay/run.relay.service << EOF
[Unit]
Description=Cardano Relay Node Run Script
Wants=network-online.target
After=multi-user.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/node.relay
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/bin/bash -c '$HOME/node.relay/run.relay.sh'
KillSignal=SIGINT
RestartKillSignal=SIGINT
TimeoutStopSec=2
SuccessExitStatus=143
SyslogIdentifier=run.relay

[Install]
WantedBy=multi-user.target
EOF

    sudo mv $HOME/node.relay/run.relay.service /etc/systemd/system/run.relay.service
    sudo systemctl daemon-reload
    sudo systemctl enable run.relay
fi

if [[ $NODE_TYPE == "bp" ]]; then
    cat > $HOME/node.bp/run.bp.service << EOF
[Unit]
Description=Cardano BP Node Run Script
Wants=network-online.target
After=multi-user.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/node.bp
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/bin/bash -c '$HOME/node.bp/run.bp.sh'
KillSignal=SIGINT
RestartKillSignal=SIGINT
TimeoutStopSec=2
SuccessExitStatus=143
SyslogIdentifier=run.bp

[Install]
WantedBy=multi-user.target
EOF
    sudo mv $HOME/node.bp/run.bp.service /etc/systemd/system/run.bp.service
    sudo systemctl daemon-reload
    sudo systemctl enable run.bp
fi

echo
echo '---------------- Preparing devops files ----------------'

sudo apt install bc tcptraceroute curl -y

# installing gLiveView tool for relay node
if [[ $NODE_TYPE == "relay" ]]; then
    cd $HOME/node.relay
    curl -s -o gLiveView.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/gLiveView.sh
    curl -s -o env https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/env
    chmod 755 gLiveView.sh

    sed -i env \
        -e "s/\#CNODE_HOME=\"\/opt\/cardano\/cnode\"/CNODE_HOME=\"\$\{HOME\}\/node.relay\"/g" \
        -e "s/CNODE_PORT=6000/CNODE_PORT=3001/g" \
        -e "s/\#CONFIG=\"\${CNODE_HOME}\/files\/config.json\"/CONFIG=\"\${CNODE_HOME}\/config\/config.json\"/g" \
        -e "s/\#SOCKET=\"\${CNODE_HOME}\/sockets\/node0.socket\"/SOCKET=\"\${CNODE_HOME}\/socket\/node.socket\"/g" \
        -e "s/\#TOPOLOGY=\"\${CNODE_HOME}\/files\/topology.json\"/TOPOLOGY=\"\${CNODE_HOME}\/config\/topology.json\"/g" \
        -e "s/\#LOG_DIR=\"\${CNODE_HOME}\/logs\"/LOG_DIR=\"\${CNODE_HOME}\/logs\"/g" \
        -e "s/\#DB_DIR=\"\${CNODE_HOME}\/db\"/DB_DIR=\"\${CNODE_HOME}\/db\"/g"
fi

# installing gLiveView tool for bp node
if [[ $NODE_TYPE == "bp" ]]; then
    cd $HOME/node.bp
    curl -s -o gLiveView.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/gLiveView.sh
    curl -s -o env https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/env
    chmod 755 gLiveView.sh

    sed -i env \
        -e "s/\#CNODE_HOME=\"\/opt\/cardano\/cnode\"/CNODE_HOME=\"\$\{HOME\}\/node.bp\"/g" \
        -e "s/CNODE_PORT=6000/CNODE_PORT=3000/g" \
        -e "s/\#CONFIG=\"\${CNODE_HOME}\/files\/config.json\"/CONFIG=\"\${CNODE_HOME}\/config\/config.json\"/g" \
        -e "s/\#SOCKET=\"\${CNODE_HOME}\/sockets\/node0.socket\"/SOCKET=\"\${CNODE_HOME}\/socket\/node.socket\"/g" \
        -e "s/\#TOPOLOGY=\"\${CNODE_HOME}\/files\/topology.json\"/TOPOLOGY=\"\${CNODE_HOME}\/config\/topology.json\"/g" \
        -e "s/\#LOG_DIR=\"\${CNODE_HOME}\/logs\"/LOG_DIR=\"\${CNODE_HOME}\/logs\"/g" \
        -e "s/\#DB_DIR=\"\${CNODE_HOME}\/db\"/DB_DIR=\"\${CNODE_HOME}\/db\"/g"
fi

echo "INIT SCRIPT COMPLETED."

