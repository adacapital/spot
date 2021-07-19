#!/bin/bash
# This is only relevant for relay nodes.

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology
NODE_HOME=$HOME/node.relay
WDIR=$HOME/node.relay/logs
JSON=$WDIR/topology_all.json

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

MY_IP=$(hostname -I | xargs)
MY_IP_PUB=""
RELAYS_COUNT=${#RELAY_IPS[@]}

if [[ $ERROR == "none" ]]; then
    echo "NODE_TYPE: $NODE_TYPE"
    echo "RELAY_IPS: ${RELAY_IPS[@]}"
    echo "RELAY_NAMES: ${RELAY_NAMES[@]}"
    echo "RELAY_IPS_PUB: ${RELAY_IPS_PUB[@]}"
else
    echo "ERROR: $ERROR"
    exit 1
fi

# define the blacklisted relay ips as the current relay pub ip
# this can be changed to all your relays if you don't want your relays to be connected to one another
# simply init BLACKLISTED_RELAYS_IPS_PUB with ${RELAY_IPS_PUB[*]}
for (( i=0; i<${RELAYS_COUNT}; i++ ));
do
    if [[ ${RELAY_IPS[$i]} == $MY_IP ]]; then
        MY_IP_PUB=${RELAY_IPS_PUB[$i]}
    fi
done

BLACKLISTED_RELAYS_IPS_PUB=$MY_IP_PUB

echo "BLACKLISTED_RELAYS_IPS_PUB: $BLACKLISTED_RELAYS_IPS_PUB"
exit 1

if [[ $NODE_TYPE == "relay" ]]; then
    # JSON=$WDIR/topology_short.json
    SCAN_FILE_SUCCESS=$WDIR/scanning_success.json
    SCAN_FILE_FAIL=$WDIR/scanning_fail.json
    SCAN_FILE_REPORT=$WDIR/scanning_report.json
    SCAN_CT_SUCCESS=0
    SCAN_CT_FAIL=0
    BLOCKPRODUCING_IP=$BP_IP
    BLOCKPRODUCING_PORT=3000

    # starting from fresh control files
    rm -f $SCAN_FILE_SUCCESS $SCAN_FILE_FAIL $SCAN_FILE_REPORT

    # download official relays tolopology filee
    curl -s https://explorer.cardano-testnet.iohkdev.io/relays/topology.json > $JSON

    # initialize SCAN_FILE_SUCCESS with our BP node
    echo -e "{\n \"addr\": \"$BLOCKPRODUCING_IP\",\n \"port\": $BLOCKPRODUCING_PORT,\n \"valency\": 1\n}," >> $SCAN_FILE_SUCCESS

    # scanning all available hosts ports and sort them by scan result
    cat $JSON | jq .Producers | jq -M -r '.[] | .addr, .port, .continent, .state' | while read -r ADDR; read -r PORT; read -r CONTINENT; read -r STATE; do
        CHK=$(netcat -w 2 -zv $ADDR $PORT 2>&1)
        if [[ $CHK == *succeeded* ]]; then
            if echo $BLACKLISTED_RELAYS_IPS_PUB | grep -q $ADDR; then
                echo "Skipping blacklisted address: $ADDR"
            else
                echo "Scanning successful: $ADDR $PORT"
                VALENCY=1
                if [[ $ADDR == "relays-new.cardano-testnet.iohkdev.io" ]]; then VALENCY=2; fi
                echo -e "{\n \"addr\": \"$ADDR\",\n \"port\": $PORT,\n \"valency\": $VALENCY,\n \"continent\": \"$CONTINENT\",\n \"state\": \"$STATE\"\n}," >> $SCAN_FILE_SUCCESS
                SCAN_CT_SUCCESS=`expr $SCAN_CT_SUCCESS + 1`
            fi
        else
            echo "Scanning failed: $ADDR $PORT"
            echo -e "{\n \"addr\": \"$ADDR\",\n \"port\": $PORT,\n \"continent\": \"$CONTINENT\",\n \"state\": \"$STATE\"\n}," >> $SCAN_FILE_FAIL
            SCAN_CT_FAIL=$((SCAN_CT_FAIL+1))
        fi
        echo "{ \"SCAN_CT_SUCCESS\": $SCAN_CT_SUCCESS, \"SCAN_CT_FAIL\": $SCAN_CT_FAIL }" > $SCAN_FILE_REPORT
    done

    echo "Scanning report:"
    cat $SCAN_FILE_REPORT

    echo "Updating tolopogy file...."
    echo -e "{ \n\"Producers\": [\n$(cat $SCAN_FILE_SUCCESS | head -n -1)} ]}" | jq . > $NODE_HOME/config/topology_with_full_scan.json

    # backup existing topology file
    cp $NODE_HOME/config/topology.json $NODE_HOME/config/topology.json.$NOW
    cp $NODE_HOME/config/topology_with_full_scan.json $NODE_HOME/config/topology.json

    # cleaning up 
    rm -f $SCAN_FILE_SUCCESS $SCAN_FILE_FAIL $SCAN_FILE_REPORT
else
    echo "This script should only be run on relay nodes."
fi


