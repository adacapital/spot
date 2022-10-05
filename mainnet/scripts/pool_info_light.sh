#!/bin/bash
# Beware this script requires some parts to be run in an air-gapped environment.
# Failure to do so will prevent the script from running.

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology

POOL_ID_HEX="22ab39540db22349b1934f5dcb7788440c33709ea9fdac07fb343395"
POOL_ID_BECH32="pool1y24nj4qdkg35nvvnfawukauggsxrxuy74876cplmxsee29w5axc"

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

if [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 ]]; then
    # retrieve the pool delegation state
    # beware this as of 2021.09.09 requires at least 14gig swap + 8gig ram
    # todo, replace with cncli stake-snapshot to be less memory intensive
    cardano-cli query pool-params --mainnet --stake-pool-id $POOL_ID_HEX > /tmp/pool-params.json
    POOL_PARAMS=$(cat /tmp/pool-params.json)

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
    "pool-params": ${POOL_PARAMS},
    "stake_distribution_rank": ${STAKE_DIST_RANK},
    "stake_distribution_fraction_pct": ${STAKE_DIST_FRACTION_PCT}
}
END
)

# # format json file
cat $HOME/node.bp/pool_info.tmp.json | jq . > $HOME/node.bp/pool_info.json
rm -f $HOME/node.bp/pool_info.tmp.json

# # display pool info json file
echo "$HOME/node.bp/pool_info.json"
cat $HOME/node.bp/pool_info.json
fi