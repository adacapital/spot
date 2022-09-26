#!/bin/bash
# Only relevant for block producing node

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology

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
    echo
else
    echo "ERROR: $ERROR"
    exit 1
fi

if [[ $NODE_TYPE == "bp" ]]; then
    CNCLI_PATH=`which cncli`
    if [[ $CNCLI_PATH == "" ]]; then
        echo "CNCLI does not seem to be installed. Please run init_cncli first."
        exit 1
    fi

    CNCLI_VERSION=`cncli --version | head -1 | awk '{print $2}'`
    RELEASETAG=$(curl -s https://api.github.com/repos/cardano-community/cncli/releases/latest | jq -r .tag_name)
    VERSION=$(echo ${RELEASETAG} | cut -c 2-)

    if [[ $CNCLI_VERSION < $RELEASETAG ]]; then
        echo "A newer version of CNCLI is available."

        if ! promptyn "Please confirm you want to install version $RELEASETAG? (y/n)"; then
            echo "Ok bye!"
            exit 1
        fi
    fi
    echo
    echo '---------------- Installing CNCLI binary ----------------'

    sudo systemctl stop cncli_sync.service

    echo "Installing CNCLI binary release ${RELEASETAG}"
    mkdir -p $HOME/download/cncli
    curl -sLJ https://github.com/cardano-community/cncli/releases/download/${RELEASETAG}/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -o $HOME/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz

    sudo tar xzvf $HOME/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -C /usr/local/bin/

    echo "Checking installed version:"
    cncli --version

    sudo systemctl daemon-reload
    sudo systemctl start cncli_sync.service

    # note cncli service logs can be seen in /var/log/syslog
else
    echo "You should only install cncli on your BP node."
fi