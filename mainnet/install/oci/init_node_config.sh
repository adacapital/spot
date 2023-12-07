#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT1="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT2="$(realpath "$(dirname "$PARENT1")")"
PARENT3="$(realpath "$(dirname "$PARENT2")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT3")")"
SPOT_DIR="$(realpath "$(dirname "$PARENT2")")"
NS_PATH="$PARENT2/scripts"
TOPO_FILE="$ROOT_PATH/pool_topology"
SPOT_ENV="${PARENT2##*/}"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "NS_PATH: $NS_PATH"
echo "ROOT_PATH: $ROOT_PATH"
echo "SPOT_ENV: $SPOT_ENV"
echo

# exit

# importing utility functions
source $NS_PATH/utils.sh

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
    echo "NODE_TYPE: $NODE_TYPE"
    echo "RELAY_IPS: ${RELAY_IPS[@]}"
    echo "RELAY_NAMES: ${RELAY_NAMES[@]}"
    echo "RELAY_IPS_PUB: ${RELAY_IPS_PUB[@]}"
else
    echo "ERROR: $ERROR"
    exit 1
fi

NODE_PATH="${ROOT_PATH}/node.${NODE_TYPE}"
# echo "NODE_PATH: $NODE_PATH"
MAGIC=$(get_network_magic)
echo "NETWORK_MAGIC: $MAGIC"



# relay node setup process
echo
CARDANO_NODE_PATH="${ROOT_PATH}/node.${NODE_TYPE}"
CARDANO_NODE_PATH=$(prompt_input_default CARDANO_NODE_PATH $CARDANO_NODE_PATH)

SPOT_DIR=$(prompt_input_default SPOT_DIR $SPOT_DIR)

SPOT_ENV=$(prompt_input_default SPOT_ENV $SPOT_ENV)

echo
echo "Details of your cardano relay node install:"
echo "CARDANO_NODE_PATH: $CARDANO_NODE_PATH"
echo "SPOT_DIR: $SPOT_DIR"
echo "SPOT_ENV: $SPOT_ENV"
if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

# # ASSUMED ALREADY DONE 
    # spot setup
    # eval cd $SPOT_DIR
    # git clone https://github.com/adacapital/spot.git

# setting up important environment variables

# Check if the CARDANO_NODE_PATH is already in .bashrc
if ! grep -q "export CARDANO_NODE_PATH" ~/.bashrc; then
    # If not, add it
    echo "export CARDANO_NODE_PATH=$CARDANO_NODE_PATH" >> ~/.bashrc
    echo "CARDANO_NODE_PATH added to .bashrc"
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "CARDANO_NODE_PATH is already defined in .bashrc"
fi

echo "\$CARDANO_NODE_SOCKET_PATH Before: $CARDANO_NODE_SOCKET_PATH"
if [[ ! ":$CARDANO_NODE_SOCKET_PATH:" == *":$CARDANO_NODE_PATH/socket/node.socket:"* ]]; then
    echo "$CARDANO_NODE_PATH/socket not found in \$CARDANO_NODE_SOCKET_PATH"
    echo "Tweaking your .bashrc"
    echo -e "\nif [[ ! \":\$CARDANO_NODE_SOCKET_PATH:\" == *\":\$CARDANO_NODE_PATH/socket/node.socket:\"* ]]; then
        export CARDANO_NODE_SOCKET_PATH=\$CARDANO_NODE_PATH/socket/node.socket
fi" >> ~/.bashrc

    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "$CARDANO_NODE_PATH/socket found in \$CARDANO_NODE_SOCKET_PATH, nothing to change here."
fi
echo "\$CARDANO_NODE_SOCKET_PATH After: $CARDANO_NODE_SOCKET_PATH"

if [[ ! ":$SPOT_PATH:" == *":$SPOT_DIR/$SPOT_ENV:"* ]]; then
    echo "$SPOT_DIR/$SPOT_ENV not found in \$SPOT_PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$SPOT_PATH':" == *":$SPOT_DIR/$SPOT_ENV:"* ]]; then
    export SPOT_PATH=$SPOT_DIR/$SPOT_ENV
fi" >> ~/.bashrc
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "$SPOT_DIR/$SPOT_ENV found in \$SPOT_PATH, nothing to change here."
fi
echo "\$SPOT_PATH After: $SPOT_PATH"

# # ASSUMED ALREADY DONE 
    # echo
    # echo "Getting node.relay folder ready..."
    # eval mkdir -p $CARDANO_NODE_PATH/config
    # eval mkdir -p $CARDANO_NODE_PATH/db
    # eval mkdir -p $CARDANO_NODE_PATH/socket


eval cd $CARDANO_NODE_PATH

# # ASSUMED ALREADY DONE 
    # eval cd $CARDANO_NODE_PATH/config
    # # wget -O config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/$SPOT_ENV/config.json
    # wget -O bgenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/$SPOT_ENV/byron-genesis.json
    # wget -O sgenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/$SPOT_ENV/shelley-genesis.json
    # wget -O agenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/$SPOT_ENV/alonzo-genesis.json
    # # wget -O topology.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/$SPOT_ENV/topology.json
    # wget -O db-sync-config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/$SPOT_ENV/db-sync-config.json
    # wget -O submit-api-config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/$SPOT_ENV/submit-api-config.json

    # cp $SCRIPT_DIR/config/node-relay-config.json ./config.json
    # sed -i "s|\/home\/cardano\/node.relay|${FULL_CARDANO_NODE_PATH}|g" config.json

    # echo
    # echo "Now tar, scp and untar to this machine a copy of a fully synched node.relay from the same environment."
    # echo
    # if ! promptyn "Please confirm you have done as requested and that you are ready to continue? (y/n)"; then
    #     echo "Ok bye!"
    #     exit 1
    # fi

echo
echo '---------------- Getting our node systemd services ready ----------------'

cat > $CARDANO_NODE_PATH/run.$NODE_TYPE.service << EOF
[Unit]
Description=Cardano $NODE_TYPE Node Run Script
Wants=network-online.target
After=multi-user.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$CARDANO_NODE_PATH
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/bin/bash -c '$CARDANO_NODE_PATH/run.$NODE_TYPE.sh'
KillSignal=SIGINT
RestartKillSignal=SIGINT
TimeoutStopSec=2
SuccessExitStatus=143
SyslogIdentifier=run.$NODE_TYPE

[Install]
WantedBy=multi-user.target
EOF

sudo mv $CARDANO_NODE_PATH/run.$NODE_TYPE.service /etc/systemd/system/run.$NODE_TYPE.service
sudo systemctl daemon-reload
sudo systemctl enable run.$NODE_TYPE

# # ASSUMED ALREADY DONE 
# # cp $SCRIPT_DIR/config/run.relay.sh .
# # cp $SCRIPT_DIR/config/topology_updater.sh .

echo
echo '---------------- Preparing devops files ----------------'

sudo apt install bc tcptraceroute curl -y


# # ASSUMED ALREADY DONE 
# # installing gLiveView tool for relay node
# eval cd $CARDANO_NODE_PATH
# curl -s -o gLiveView.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/gLiveView.sh
# curl -s -o env https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/env
# chmod 755 gLiveView.sh

# sed -i env \
#     -e "s/\#CNODE_HOME=\"\/opt\/cardano\/cnode\"/CNODE_HOME=\"\$\{CARDANO_NODE_PATH\}\"/g" \
#     -e "s/CNODE_PORT=6000/CNODE_PORT=3001/g" \
#     -e "s/\#CONFIG=\"\${CNODE_HOME}\/files\/config.json\"/CONFIG=\"\${CARDANO_NODE_PATH}\/config\/config.json\"/g" \
#     -e "s/\#SOCKET=\"\${CNODE_HOME}\/sockets\/node0.socket\"/SOCKET=\"\${CARDANO_NODE_PATH}\/socket\/node.socket\"/g" \
#     -e "s/\#TOPOLOGY=\"\${CNODE_HOME}\/files\/topology.json\"/TOPOLOGY=\"\${CARDANO_NODE_PATH}\/config\/topology.json\"/g" \
#     -e "s/\#LOG_DIR=\"\${CNODE_HOME}\/logs\"/LOG_DIR=\"\${CARDANO_NODE_PATH}\/logs\"/g" \
#     -e "s/\#DB_DIR=\"\${CNODE_HOME}\/db\"/DB_DIR=\"\${CARDANO_NODE_PATH}\/db\"/g"

echo 
echo '---------------- Getting our firewall ready ----------------'

sudo apt-get install firewalld 
sudo systemctl enable firewalld
sudo systemctl start firewalld 

if [ "$NODE_TYPE" == "relay" ]; then
    echo "Configuring for relay node..."
    sudo firewall-cmd --zone=public --add-port=3001/tcp --permanent
    sudo firewall-cmd --reload
    sudo firewall-cmd --list-all

elif [ "$NODE_TYPE" == "bp" ]; then
    echo "Configuring for bp node..."
    sudo firewall-cmd --zone=public --add-port=3000/tcp --permanent
    sudo firewall-cmd --reload
    sudo firewall-cmd --list-all

else
    echo "NODE_TYPE is not set to 'relay' or 'bp'. No changes made."
fi