#!/bin/bash

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology

if [[ $# -eq 2 && ! $1 == "" && ! $2 == "" ]]; then VOTE_TX_HASH=$1; COLD_VKEY_HASH=$2;
else 
    echo -e "This script requires input parameters:\n\tUsages:"
    echo -e "\t\t$0 {vote_transaction_hash} {pool_cold_vkey_hash}"
    exit 2
fi

# spot/mainnet/scripts/spo_poll_vote.sh fae7bda85acb99c513aeab5f86986047b6f6cbd33a8e11f11c5005513a054dc8 22ab39540db22349b1934f5dcb7788440c33709ea9fdac07fb343395

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
    STATE_STEP_ID=0
    STATE_SUB_STEP_ID="build.trans"
    STATE_LAST_DATE="never"
    STATE_TRANS_WORK_DIR=""
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR
fi

print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR $META_URL $META_DATA_HASH $MIN_POOL_COST

# To prepare COLD_VKEY_HASH run either of these 2 commands on your airgap environment
# cardano-cli stake-pool id --cold-verification-key-file $COLD_VKEY_FILE --output-format hex > pool.hex.id
# OR
# vkeyNodeHash=$(cat $COLD_VKEY_FILE | jq -r .cborHex | tail -c +5 | xxd -r -ps | b2sum -l 224 -b | cut -d' ' -f 1)


if [[ $STATE_SUB_STEP_ID == "build.trans" && $IS_AIR_GAPPED == 0 ]]; then
    cd ~

    URL="https://raw.githubusercontent.com/cardano-foundation/CIP-0094-polls/main/networks/mainnet/${VOTE_TX_HASH}/poll.json"
    wget $URL

    cardano-cli governance answer-poll --poll-file poll.json > poll-answer.json

    echo "STARTING THE VOTE TRANSACTION PROCESS..."

    $SPOT_DIR/scripts/create_transaction.sh $(cat $HOME/keys/paymentwithstake.addr) NONE NONE NONE $HOME/poll-answer.json $COLD_VKEY_HASH
elif [[ $STATE_SUB_STEP_ID == "sign.trans" && $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 ]]; then

    $SPOT_DIR/scripts/create_transaction.sh $(cat $HOME/keys/paymentwithstake.addr) $HOME/keys/payment.skey $HOME/cold_keys/cold.skey $HOME/cold_keys/cold.vkey NONE NONE

elif [[ $STATE_SUB_STEP_ID == "submit.trans" && $IS_AIR_GAPPED == 0 ]]; then

    $SPOT_DIR/scripts/create_transaction.sh NONE NONE NONE NONE NONE NONE

fi

echo "VOTING PROCESS COMPLETE."
