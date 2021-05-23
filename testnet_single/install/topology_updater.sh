#!/bin/bash
now=`date +"%Y%m%d_%H%M%S"`
USERNAME=$(whoami)
CNODE_PORT=3001 # must match your relay node port as set in the startup command
CNODE_HOSTNAME="CHANGE ME"  # optional. must resolve to the IP you are requesting from
CNODE_BIN="/usr/local/bin"
CNODE_HOME=$HOME/node.relay
CNODE_LOG_DIR=${CNODE_HOME}/logs
GENESIS_JSON=$CNODE_HOME/config/sgenesis.json
NETWORKID=$(cat $GENESIS_JSON | jq -r .networkId)
CNODE_VALENCY=1   # optional for multi-IP hostnames
NWMAGIC=$(cat $GENESIS_JSON | jq -r .networkMagic)

if [[ $NETWORKID == "Mainnet" ]]; then NETWORK_IDENTIFIER="--mainnet"; else NETWORK_IDENTIFIER="--testnet-magic $NWMAGIC"; fi

BLOCK_NO=$(cardano-cli query tip $NETWORK_IDENTIFIER | jq -r .block )
 
# Note:
# if you run your node in IPv4/IPv6 dual stack network configuration and want announced the
# IPv4 address only please add the -4 parameter to the curl command below  (curl -4 -s ...)
if [[ $CNODE_HOSTNAME != "CHANGE ME" ]]; then
    T_HOSTNAME="&hostname=$CNODE_HOSTNAME"
else
    T_HOSTNAME=''
fi

echo "CNODE_PORT: $CNODE_PORT"
echo "CNODE_HOSTNAME: $CNODE_HOSTNAME"
echo "CNODE_HOME: $CNODE_HOME"
echo "CNODE_LOG_DIR: $CNODE_LOG_DIR"
echo "GENESIS_JSON: $GENESIS_JSON"
echo "NETWORKID: $NETWORKID"
echo "NWMAGIC: $NWMAGIC"
echo "NETWORK_IDENTIFIER: $NETWORK_IDENTIFIER"
echo "BLOCK_NO: $BLOCK_NO"
echo "T_HOSTNAME: $T_HOSTNAME"

if [[ ! -d $CNODE_LOG_DIR ]]; then
    mkdir -p $CNODE_LOG_DIR
fi

URL="https://api.clio.one/htopology/v1/?port=$CNODE_PORT&blockNo=$BLOCK_NO&valency=$CNODE_VALENCY&magic=$NWMAGIC$T_HOSTNAME"
echo "URL: $URL"

curl -4 -s "https://api.clio.one/htopology/v1/?port=$CNODE_PORT&blockNo=$BLOCK_NO&valency=$CNODE_VALENCY&magic=$NWMAGIC$T_HOSTNAME" | tee -a $CNODE_LOG_DIR/topology_updater_lastresult.json