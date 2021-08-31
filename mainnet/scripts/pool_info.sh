#!/bin/bash
# Beware this script requires some parts to be run in an air-gapped environment.
# Failure to do so will prevent the script from running.

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

IS_AIR_GAPPED=0
if [[ $NODE_TYPE == "airgap" ]]; then
    # checking we're in an air-gapped environment
    if ping -q -c 1 -W 1 google.com >/dev/null; then
        echo "The network is up"
    else
        echo "The network is down"
    fi

    IS_AIR_GAPPED=$(check_air_gap)

    if [[ $IS_AIR_GAPPED == 1 ]]; then
        echo "we are air-gapped"
    else
        echo "we are online"
    fi
fi

# getting the script state ready
STATE_FILE="$HOME/spot.state"

if [ -f "$STATE_FILE" ]; then
    # Source the state file to restore state
    . "$STATE_FILE" 2>/dev/null || :
else
    touch $STATE_FILE
    STATE_STEP_ID=4
    STATE_SUB_STEP_ID="init"
    STATE_LAST_DATE="never"
    STATE_TRANS_WORK_DIR=""
    POOL_ID_BECH32=""
    POOL_ID_HEX=""
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE POOL_ID_BECH32 POOL_ID_HEX
fi

print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $POOL_ID_BECH32 $POOL_ID_HEX

if [[ -s $HOME/node.bp/pool_info.json ]]; then
    POOL_ID_BECH32=$(cat node.bp/pool_info.json | jq .pool_id_bech32)
    POOL_ID_HEX=$(cat node.bp/pool_info.json | jq .pool_id_hex)

    STATE_SUB_STEP_ID="get_info"
else
    if [[ $STATE_SUB_STEP_ID != "get_info" ]]; then
        if [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 ]]; then
            # retrieve pool identifiers
            POOL_ID_BECH32=$(cardano-cli stake-pool id --cold-verification-key-file $HOME/cold_keys/cold.vkey)
            POOL_ID_HEX=$(cardano-cli stake-pool id --cold-verification-key-file $HOME/cold_keys/cold.vkey --output-format hex)

            STATE_STEP_ID=4
            STATE_SUB_STEP_ID="get_info"
            STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
            save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE POOL_ID_BECH32 POOL_ID_HEX

            # make sure path to usb key is set as a global variable and add it to .bashrc
            if [[ -z "$SPOT_USB_KEY" ]]; then
                read -p "Enter path to usb key directory to be used to move data between offline and online environments: " SPOT_USB_KEY
            
                # add it to .bashrc
                echo $"if [[ -z \$SPOT_USB_KEY ]]; then
            export SPOT_USB_KEY=$SPOT_USB_KEY
        fi" >> ~/.bashrc
                eval "$(cat ~/.bashrc | tail -n +10)"
                echo "\$SPOT_USB_KEY After: $SPOT_USB_KEY"
            fi

            # copy certain files to usb key to continue operations on bp node
            cp $STATE_FILE $SPOT_USB_KEY

            echo
            echo "Now copy all files in $SPOT_USB_KEY to your bp node home folder and run pool_info.sh to complete this operation."
        else
            echo "This script requires to retrieve pool identifiers from an air-gapped environment as doing make use of cold keys."
            echo "Please rerun this script from an air-gapped environment."
            echo "Bye for now!"
            exit 1
        fi
    fi
fi

if [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 4 && $STATE_SUB_STEP_ID == "get_info" ]]; then
    # retrieve the pool delegation state
    REG_JSON=$(cardano-cli query ledger-state --mainnet | jq '.stateBefore.esLState.delegationState.pstate."pParams pState".'\"$POOL_ID_HEX\"'')

    # retrieve the pool's stake distribution and rank
    STAKE_DIST=$(cardano-cli query stake-distribution --mainnet | sort -rgk2 | head -n -2 | nl | grep $POOL_ID_BECH32)
    STAKE_DIST_RANK=$(echo $STAKE_DIST | awk '{print $1}')
    STAKE_DIST_FRACTION_DEC=$(echo $STAKE_DIST | awk '{print $3}' | awk -F"E" 'BEGIN{OFMT="%10.10f"} {print $1 * (10 ^ $2)}')
    STAKE_DIST_FRACTION_PCT=$(echo $STAKE_DIST_FRACTION_DEC*100 | bc )

# build the pool info json file
$(cat <<-END > $HOME/node.bp/pool_info.tmp.json
{
    "pool_id_bech32": "${POOL_ID_BECH32}", 
    "pool_id_hex": "${POOL_ID_HEX}", 
    "delegation_state": ${REG_JSON},
    "stake_distribution_rank": ${STAKE_DIST_RANK},
    "stake_distribution_fraction_pct": ${STAKE_DIST_FRACTION_PCT}
}
END
)

# format json file
cat $HOME/node.bp/pool_info.tmp.json | jq . > $HOME/node.bp/pool_info.json
rm -f $HOME/node.bp/pool_info.tmp.json

# display pool info json file
echo "$HOME/node.bp/pool_info.json"
cat $HOME/node.bp/pool_info.json
fi