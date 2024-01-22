#!/bin/bash
# In a real life scenario (MAINNET), you need to have your keys under cold storage.
# We're ok here as we're only playing with TESTNET.

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=$ROOT_PATH/pool_topology


echo "UPDATE POOL REGISTRATION STARTING..."
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "ROOT_PATH: $ROOT_PATH"
echo "NS_PATH: $NS_PATH"
echo "TOPO_FILE: $TOPO_FILE"

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

NODE_PATH="$ROOT_PATH/node.bp"
MAGIC=$(get_network_magic)
echo "NODE_PATH: $NODE_PATH"
echo "NETWORK_MAGIC: $MAGIC"


cd $ROOT_PATH
cd pool_keys

if [ -f "$ROOT_PATH/pool_keys/kes.skey" ]; then
    echo
    echo '---------------- Backing up previous KES key pair ----------------'
    chmod 664 $ROOT_PATH/pool_keys/kes.vkey
    chmod 664 $ROOT_PATH/pool_keys/kes.skey
    mv $ROOT_PATH/pool_keys/kes.vkey $ROOT_PATH/pool_keys/kes.vkey.$NOW
    mv $ROOT_PATH/pool_keys/kes.skey $ROOT_PATH/pool_keys/kes.skey.$NOW
    chmod 400 $ROOT_PATH/pool_keys/kes.vkey.$NOW
    chmod 400 $ROOT_PATH/pool_keys/kes.skey.$NOW
fi


if [ -f "$ROOT_PATH/pool_keys/node.cert" ]; then
    echo
    echo '---------------- Backing up previous operational certificate ----------------'
    chmod 664 $ROOT_PATH/pool_keys/node.cert
    mv $ROOT_PATH/pool_keys/node.cert $ROOT_PATH/pool_keys/node.cert.$NOW
    chmod 400 $ROOT_PATH/pool_keys/node.cert.$NOW
fi


echo
echo '---------------- Generating KES key pair ----------------'

cardano-cli node key-gen-KES \
--verification-key-file kes.vkey \
--signing-key-file kes.skey

chmod 400 kes.skey

echo
echo '---------------- Generating the operational certificate ----------------'

SLOTSPERKESPERIOD=$(cat $ROOT_PATH/node.bp/config/sgenesis.json | jq -r '.slotsPerKESPeriod')
CTIP=$(cardano-cli query tip --socket-path $ROOT_PATH/node.bp/socket/node.socket --testnet-magic $MAGIC | jq -r .slot)
KES_PERIOD=$(expr $CTIP / $SLOTSPERKESPERIOD)
echo "SLOTSPERKESPERIOD: $SLOTSPERKESPERIOD"
echo "CTIP: $CTIP"
echo "KES_PERIOD: $KES_PERIOD"

cardano-cli node issue-op-cert \
--kes-verification-key-file kes.vkey \
--cold-signing-key-file cold.skey \
--operational-certificate-issue-counter cold.counter \
--kes-period $KES_PERIOD \
--out-file node.cert

echo
echo '---------------- Restarting bp node ----------------'

sudo systemctl restart run.bp.service