#!/bin/bash
# Only relevant for block producing node

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT1="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT2="$(realpath "$(dirname "$PARENT1")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT2")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE="$ROOT_PATH/pool_topology"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "NS_PATH: $NS_PATH"
echo "ROOT_PATH: $ROOT_PATH"
echo

# importing utility functions
source $NS_PATH/utils.sh

# calculating the shelley hash
SHELLEY_GENESIS_HASH=$(cardano-cli genesis hash --genesis $ROOT_PATH/node.bp/config/sgenesis.json)

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
MAGIC=$(get_network_magic)
echo "NETWORK_MAGIC: $MAGIC"
echo "NODE_PATH: $NODE_PATH"

if [[ $NODE_TYPE == "bp" ]]; then
    echo
    echo '---------------- Installing CNCLI binary ----------------'

    RELEASETAG=$(curl -s https://api.github.com/repos/cardano-community/cncli/releases/latest | jq -r .tag_name)
    VERSION=$(echo ${RELEASETAG} | cut -c 2-)
    echo "VERSION: $VERSION"
    echo "Installing CNCLI binary release ${RELEASETAG}"
    mkdir -p $ROOT_PATH/download/cncli
    curl -sLJ https://github.com/cardano-community/cncli/releases/download/${RELEASETAG}/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -o $ROOT_PATH/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz

    sudo tar xzvf $ROOT_PATH/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -C /usr/local/bin/

    echo "Checking installed version:"
    cncli -V

    echo "Setting up CNCLI SYNC as a service"
    BLOCKPRODUCING_IP=$BP_IP
    BLOCKPRODUCING_PORT=3000

    mkdir -p $ROOT_PATH/node.bp/cncli

    cat > $ROOT_PATH/node.bp/cncli/cncli_sync.service << EOF
[Unit]
Description=CNCLI Sync
After=multi-user.target

[Service]
User=$USER
Type=simple
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/usr/local/bin/cncli sync --network-magic 1097911063 --host $BLOCKPRODUCING_IP --port $BLOCKPRODUCING_PORT --db $ROOT_PATH/node.bp/cncli/cncli.db --shelley-genesis-hash $SHELLEY_GENESIS_HASH
KillSignal=SIGINT
SuccessExitStatus=143
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=cncli_sync

[Install]
WantedBy=multi-user.target
EOF

    sudo mv $ROOT_PATH/node.bp/cncli/cncli_sync.service /etc/systemd/system/cncli_sync.service

    sudo systemctl daemon-reload
    sudo systemctl enable cncli_sync
    sudo systemctl start cncli_sync.service

    # note cncli service logs can be seen in /var/log/syslog
else
    echo "You should only install cncli on your BP node."
fi