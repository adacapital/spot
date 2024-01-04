#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT1="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT2="$(realpath "$(dirname "$PARENT1")")"
PARENT3="$(realpath "$(dirname "$PARENT2")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT3")")/preview"
SPOT_DIR="$(realpath "$(dirname "$PARENT2")")"
NS_PATH="$PARENT2/scripts"
TOPO_FILE="$ROOT_PATH/pool_topology"
SPOT_ENV="${PARENT2##*/}"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "NS_PATH: $NS_PATH"
echo "ROOT_PATH: $ROOT_PATH"
echo "SPOT_ENV: $SPOT_ENV"
echo "TOPO_FILE: $TOPO_FILE"
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

# exit

# relay node setup process
echo
CARDANO_NODE_BP_PATH="${ROOT_PATH}/node.bp"
CARDANO_NODE_BP_PATH=$(prompt_input_default CARDANO_NODE_BP_PATH $CARDANO_NODE_BP_PATH)
CARDANO_NODE_RELAY_PATH="${ROOT_PATH}/node.relay"
CARDANO_NODE_RELAY_PATH=$(prompt_input_default CARDANO_NODE_RELAY_PATH $CARDANO_NODE_RELAY_PATH)

SPOT_DIR=$(prompt_input_default SPOT_DIR $SPOT_DIR)

SPOT_ENV=$(prompt_input_default SPOT_ENV $SPOT_ENV)

echo
echo "Details of your cardano relay node install:"
echo "CARDANO_NODE_BP_PATH: $CARDANO_NODE_BP_PATH"
echo "CARDANO_NODE_RELAY_PATH: $CARDANO_NODE_RELAY_PATH"
echo "SPOT_DIR: $SPOT_DIR"
echo "SPOT_ENV: $SPOT_ENV"
if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi


echo
echo '---------------- Getting our node systemd services ready ----------------'

cat > $CARDANO_NODE_BP_PATH/run.bp-preview.service << EOF
[Unit]
Description=Cardano BP Node Run Script
Wants=network-online.target
After=multi-user.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$CARDANO_NODE_BP_PATH
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/bin/bash -c '$CARDANO_NODE_BP_PATH/run.bp.sh'
KillSignal=SIGINT
RestartKillSignal=SIGINT
TimeoutStopSec=2
SuccessExitStatus=143
SyslogIdentifier=run.preview.bp

[Install]
WantedBy=multi-user.target
EOF

sudo mv $CARDANO_NODE_BP_PATH/run.bp-preview.service /etc/systemd/system/run.bp-preview.service
sudo systemctl daemon-reload
sudo systemctl enable run.bp-preview


cat > $CARDANO_NODE_RELAY_PATH/run.relay-preview.service << EOF
[Unit]
Description=Cardano Relay Node Run Script
Wants=network-online.target
After=multi-user.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$CARDANO_NODE_RELAY_PATH
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/bin/bash -c '$CARDANO_NODE_RELAY_PATH/run.relay.sh'
KillSignal=SIGINT
RestartKillSignal=SIGINT
TimeoutStopSec=2
SuccessExitStatus=143
SyslogIdentifier=run.preview.relay

[Install]
WantedBy=multi-user.target
EOF

sudo mv $CARDANO_NODE_RELAY_PATH/run.relay-preview.service /etc/systemd/system/run.relay-preview.service
sudo systemctl daemon-reload
sudo systemctl enable run.relay-preview

echo 
echo '---------------- Getting our firewall ready ----------------'

sudo apt-get install firewalld 
sudo systemctl enable firewalld
sudo systemctl start firewalld 

sudo firewall-cmd --zone=public --add-port=6001/tcp --permanent
sudo firewall-cmd --zone=public --add-port=6000/tcp --permanent
sudo firewall-cmd --reload
sudo firewall-cmd --list-all