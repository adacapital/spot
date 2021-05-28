#!/bin/bash
# This is only relevant for relay nodes.

now=`date +"%Y%m%d_%H%M%S"`
# relay node home directory
NODE_HOME=$HOME/node.relay

# copy topology_updater script to its target directory
cp $SPOT_PATH/install/topology_updater.sh $NODE_HOME

# Schedule topology_updater to run every hour
# todo check if topology_updater is not already in crontab, if so skip this step
cat > $NODE_HOME/crontab-fragment.txt << EOF
28 * * * * ${NODE_HOME}/topology_updater.sh
EOF
crontab -l | cat - $NODE_HOME/crontab-fragment.txt >$NODE_HOME/crontab.txt && crontab $NODE_HOME/crontab.txt
rm $NODE_HOME/crontab-fragment.txt

# After 4 hours update your relay node topology file
TOPO_UDT_CNT=$(cat $NODE_HOME/logs/topology_updater_lastresult.json | wc -l)

echo "TOPO_UDT_CNT: $TOPO_UDT_CNT"

if [[ $TOPO_UDT_CNT -gt 3 ]]; then
    echo "Updating relay node topology file..."
    BLOCKPRODUCING_IP="127.0.0.1"
    BLOCKPRODUCING_PORT=3000
    MAX_PEERS=20
    # backup existing topology file
    cp $NODE_HOME/config/topology.json $NODE_HOME/config/topology.json.$now
    curl -s -o $NODE_HOME/config/topology.json.new "https://api.clio.one/htopology/v1/fetch/?max=$MAX_PEERS&magic=1097911063&customPeers=$BLOCKPRODUCING_IP:$BLOCKPRODUCING_PORT:1|relays-new.cardano-testnet.iohkdev.io:3001:2"

    echo "{ \"Producers\": $(cat node.relay/config/topology.json.new | jq .Producers) }" > $NODE_HOME/config/topology.json

    # restart relay node
    # sudo systemctl restart cardano-node
else
    HOURS=`expr 4 - $TOPO_UDT_CNT`
    echo "Another $HOURS hour(s) to wait before the relay topology file can be updated!"
fi