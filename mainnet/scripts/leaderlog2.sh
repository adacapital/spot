#!/bin/bash
# Only relevant for block producing node

if [[ $1 == "--help" || $1 == "--h" ]]; then 
    echo -e "Usage: $0 {epoch [prev, current, next]; default:next} {timezone; default:UTC}"
    exit 2
fi

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
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

if [[ $NODE_TYPE == "bp" ]]; then
    CNCLI_STATUS=$($NS_PATH/cncli_status.sh | jq -r .status)
    EPOCH="${1:-next}"
    TIMEZONE="${2:-UTC}"
    POOL_ID=$(cat $HOME/node.bp/pool_info.json | jq -r .pool_id_hex)
    echo "EPOCH: $EPOCH"
    echo "TIMEZONE: $TIMEZONE"
    echo "POOL_ID: $POOL_ID"

    function getLeader() {
        # echo "getLeader, pool-stake $1, active-stake $2"
        /usr/local/bin/cncli leaderlog \
            --db $HOME/node.bp/cncli/cncli.db \
            --pool-id  $POOL_ID \
            --pool-vrf-skey $HOME/pool_keys/vrf.skey \
            --byron-genesis $HOME/node.bp/config/bgenesis.json \
            --shelley-genesis $HOME/node.bp/config/sgenesis.json \
            --pool-stake $1 \
            --active-stake $2 \
            --ledger-set $EPOCH \
            --tz $TIMEZONE
    }

    if [[ $CNCLI_STATUS == "ok" ]]; then
        echo "CNCLI database is synced."

        SNAPSHOT=$(cardano-cli query stake-snapshot --stake-pool-id $POOL_ID --mainnet)

        if [[ $EPOCH == "next" ]]; then
            POOL_STAKE=$(echo "$SNAPSHOT" | grep -oP '(?<=    "poolStakeMark": )\d+(?=,?)')
            ACTIVE_STAKE=$(echo "$SNAPSHOT" | grep -oP '(?<=    "activeStakeMark": )\d+(?=,?)')
        elif [[ $EPOCH == "current" ]]; then
            POOL_STAKE=$(echo "$SNAPSHOT" | grep -oP '(?<=    "poolStakeSet": )\d+(?=,?)')
            ACTIVE_STAKE=$(echo "$SNAPSHOT" | grep -oP '(?<=    "activeStakeSet": )\d+(?=,?)')
        elif [[ $EPOCH == "prev" ]]; then
            echo "Unsupported EPOCH value (prev) in this version of the leaderlog script."
            exit 1
        fi

        echo $SNAPSHOT
        echo "POOL_STAKE: $(echo $POOL_STAKE | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')"
        echo "ACTIVE_STAKE: $(echo $ACTIVE_STAKE | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')"

        mv $HOME/node.bp/cncli/leaderlog.json $HOME/node.bp/cncli/leaderlog.$NOW.json
        getLeader "$POOL_STAKE" "$ACTIVE_STAKE" > $HOME/node.bp/cncli/leaderlog.json

        LOG=$HOME/node.bp/cncli/leaderlog.json

        EPOCH_=$(cat $LOG | jq .epoch)
        echo "\`Epoch $EPOCH_\` 🧙🔮:"

        SLOTS=$(cat $LOG | jq .epochSlots)
        IDEAL=$(cat $LOG | jq .epochSlotsIdeal)
        PERFORMANCE=$(cat $LOG | jq .maxPerformance)
        echo "\`ADACT  - $SLOTS \`🎰\`,  $PERFORMANCE% \`🍀max, \`$IDEAL\` 🧱ideal"

        echo "leaderlog produced: $LOG"

        # remove leaderlogs older than 15 days
        find $HOME/node.bp/cncli/. -name "leaderlog.*.json" -mtime +15 -exec rm -f '{}' \;
    else
        echo "CNCLI database not synced!!!"
    fi
else
    echo "You should only install cncli on your BP node."
fi
