#!/bin/bash
# This is only relevant for relay nodes.

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
else
    echo "ERROR: $ERROR"
    exit 1
fi

if [[ $NODE_TYPE == "relay" ]]; then
    # relay node home directory
    NODE_HOME=$HOME/node.relay

    # copy topology_updater script to its target directory
    cp $SPOT_PATH/install/topology_updater.sh $NODE_HOME

    if [[ $(crontab -l | egrep -v "^(#|$)" | grep -q 'topology_updater'; echo $?) == 1 ]]; then
        echo "No cron entry found. Adding it."

        # Schedule topology_updater to run every hour
        # todo check if topology_updater is not already in crontab, if so skip this step
        cat > $NODE_HOME/crontab-fragment.txt << EOF
28 * * * * ${NODE_HOME}/topology_updater.sh
EOF
        crontab -l | cat - $NODE_HOME/crontab-fragment.txt >$NODE_HOME/crontab.txt && crontab $NODE_HOME/crontab.txt
        rm $NODE_HOME/crontab-fragment.txt
    else
        echo "Cron entry found."
    fi

    # After 4 hours update your relay node topology file
    TOPO_UDT_CNT=$(cat $NODE_HOME/logs/topology_updater_lastresult.json | wc -l)

    echo "TOPO_UDT_CNT: $TOPO_UDT_CNT"

    if [[ $TOPO_UDT_CNT -gt 3 ]]; then
        echo "Updating relay node topology file..."
        BLOCKPRODUCING_IP=$BP_IP
        BLOCKPRODUCING_PORT=3000
        MAX_PEERS=20

        echo "BLOCKPRODUCING_IP: $BLOCKPRODUCING_IP"
        echo "BLOCKPRODUCING_PORT: $BLOCKPRODUCING_PORT"
        
        # backup existing topology file
        cp $NODE_HOME/config/topology.json $NODE_HOME/config/topology.json.$now
        curl -s -o $NODE_HOME/config/topology.json.new "https://api.clio.one/htopology/v1/fetch/?max=$MAX_PEERS&magic=764824073&customPeers=$BLOCKPRODUCING_IP:$BLOCKPRODUCING_PORT:1|relays-new.cardano-mainnet.iohk.io:3001:2"

        echo "{ \"Producers\": $(cat node.relay/config/topology.json.new | jq .Producers) }" > $NODE_HOME/config/topology.json

        echo "Topology candidate:"
        cat $NODE_HOME/config/topology.json.new

        echo "Restarting the relay..."
        sudo systemctl restart run.relay
    else
        HOURS=`expr 4 - $TOPO_UDT_CNT`
        echo "Another $HOURS hour(s) to wait before the relay topology file can be updated!"
    fi
else
    echo "This script should only be run on relay nodes."
fi