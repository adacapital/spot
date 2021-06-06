#!/bin/bash
# This is only relevant for relay nodes.

# useful variables
NOW=`date +"%Y%m%d_%H%M%S"`
NODE_HOME=$HOME/node.relay
WDIR=$HOME/node.relay/logs
JSON=$WDIR/topology_all.json
# JSON=$WDIR/topology_short.json
SCAN_FILE_SUCCESS=$WDIR/scanning_success.json
SCAN_FILE_FAIL=$WDIR/scanning_fail.json
SCAN_FILE_REPORT=$WDIR/scanning_report.json
SCAN_CT_SUCCESS=0
SCAN_CT_FAIL=0
BLAKCLIST_ADDR="51.104.251.142"
BLOCKPRODUCING_IP="127.0.0.1"
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
        if echo $BLAKCLIST_ADDR | grep -q $ADDR; then
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


