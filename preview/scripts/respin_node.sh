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

# respining the nodes
if [[ $NODE_TYPE == "bp" ]]; then
    echo
    echo '---------------- Shutting down some services  ----------------'
    if ! promptyn "Proceed with shutting down nodes and cncli? (y/n)"; then
        echo "Ok bye for now!"
        exit 1
    fi

    sudo systemctl stop cncli_sync
    sudo systemctl stop run.relay.service
    sudo systemctl stop run.bp.service
    echo
    echo "Shutdown done!"

    echo
    echo '---------------- Purging db ----------------'
    if ! promptyn "Proceed with purging the node's db? (y/n)"; then
        echo "Ok bye for now!"
        exit 1
    fi

    # purging the bp node's db
    rm -rf $HOME/node.bp/db/*
    rm -f $HOME/node.bp/cncli/cncli.db*
    rm -rf $HOME/node.bp/logs

    # purging the relay node's db
    rm -rf $HOME/node.relay/db/*
    rm -rf $HOME/node.relay/logs
    echo
    echo "DB purge done!"

    echo
    echo '---------------- Backing up config files ----------------'
    if ! promptyn "Proceed with backing up config files? (y/n)"; then
        echo "Ok bye for now!"
        exit 1
    fi

    mkdir $HOME/node.bp/config/bkup_$NOW
    cp $HOME/node.bp/config/*.json $HOME/node.bp/config/bkup_$NOW

    mkdir $HOME/node.relay/config/bkup_$NOW
    cp $HOME/node.relay/config/*.json $HOME/node.relay/config/bkup_$NOW

    mkdir -p $HOME/node.bp/config/config_master
    rm -f $HOME/node.bp/config/config_master/*
    cd $HOME/node.bp/config/config_master

    wget -O config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/config.json
    wget -O bgenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/byron-genesis.json
    wget -O sgenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/shelley-genesis.json
    wget -O agenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/alonzo-genesis.json
    wget -O topology.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/topology.json
    wget -O db-sync-config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/db-sync-config.json
    wget -O submit-api-config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/submit-api-config.json
 
    mkdir -p $HOME/node.relay/config/config_master
    rm -f $HOME/node.relay/config/config_master/*
    cd $HOME/node.relay/config/config_master

    wget -O config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/config.json
    wget -O bgenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/byron-genesis.json
    wget -O sgenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/shelley-genesis.json
    wget -O agenesis.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/alonzo-genesis.json
    wget -O topology.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/topology.json
    wget -O db-sync-config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/db-sync-config.json
    wget -O submit-api-config.json https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/submit-api-config.json
 

    echo "Config file backup done!"

    echo
    echo "Now please compare changes between config_master config files and live ones for both bp and relay nodes, then promote manually the relevant changes to the config files in $HOME/node.bp/config and $HOME/node.relay/config."
    echo
    echo "Warning: if sgenesis.json changed you will have to change  --shelley-genesis-hash in /etc/systemd/system/cncli_sync.service to the new hash, then run sudo systemctl daemon-reload for the change to take effect!"
    #TODO automate this cncli config step

    echo
    if ! promptyn "Ready to proceed? (y/n)"; then
        echo "Ok bye for now!"
        exit 1
    fi

    echo
    echo "You can now restart the relay and bp nodes."
    echo "You should start the bp in relay mode only by running $HOME/run.bp.respin.sh"
    echo "Once fully in sync you should then re-register your pool."
fi