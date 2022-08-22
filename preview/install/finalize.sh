#!/bin/bash

echo
echo '---------------- Preparing run files ----------------'
# copy run scripts to their target location
cp $SPOT_PATH/install/run.relay.sh $HOME/node.relay
cp $SPOT_PATH/install/run.bp.sh $HOME/node.bp

# create services to run our nodes scripts
cat > $HOME/node.relay/run.relay.service << EOF
[Unit]
Description=Cardano Relay Node Run Script
Wants=network-online.target
After=multi-user.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/node.relay
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/bin/bash -c '$HOME/node.relay/run.relay.sh'
KillSignal=SIGINT
RestartKillSignal=SIGINT
TimeoutStopSec=2
SuccessExitStatus=143
SyslogIdentifier=run.relay

[Install]
WantedBy=multi-user.target
EOF

sudo mv $HOME/node.relay/run.relay.service /etc/systemd/system/run.relay.service

cat > $HOME/node.bp/run.bp.service << EOF
[Unit]
Description=Cardano BP Node Run Script
Wants=network-online.target
After=multi-user.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/node.bp
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/bin/bash -c '$HOME/node.bp/run.bp.sh'
KillSignal=SIGINT
RestartKillSignal=SIGINT
TimeoutStopSec=2
SuccessExitStatus=143
SyslogIdentifier=run.bp

[Install]
WantedBy=multi-user.target
EOF

sudo mv $HOME/node.bp/run.bp.service /etc/systemd/system/run.bp.service

sudo systemctl daemon-reload
sudo systemctl enable run.relay
sudo systemctl enable run.bp


# echo
# echo '---------------- Preparing devops files ----------------'
# # todo cp devops scripts
# sudo apt install bc tcptraceroute curl -y

# # installing gLiveView tool for relay node
# cd ~/node.relay
# curl -s -o gLiveView.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/gLiveView.sh
# curl -s -o env https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/env
# chmod 755 gLiveView.sh

# sed -i env \
#     -e "s/\#CNODE_HOME=\"\/opt\/cardano\/cnode\"/CNODE_HOME=\"\$\{HOME\}\/node.relay\"/g" \
#     -e "s/CNODE_PORT=6000/CNODE_PORT=3001/g" \
#     -e "s/\#CONFIG=\"\${CNODE_HOME}\/files\/config.json\"/CONFIG=\"\${CNODE_HOME}\/config\/config.json\"/g" \
#     -e "s/\#SOCKET=\"\${CNODE_HOME}\/sockets\/node0.socket\"/SOCKET=\"\${CNODE_HOME}\/socket\/node.socket\"/g" \
#     -e "s/\#TOPOLOGY=\"\${CNODE_HOME}\/files\/topology.json\"/TOPOLOGY=\"\${CNODE_HOME}\/config\/topology.json\"/g" \
#     -e "s/\#LOG_DIR=\"\${CNODE_HOME}\/logs\"/LOG_DIR=\"\${CNODE_HOME}\/logs\"/g" \
#     -e "s/\#DB_DIR=\"\${CNODE_HOME}\/db\"/DB_DIR=\"\${CNODE_HOME}\/db\"/g"


# # installing gLiveView tool for bp node
# cd ~/node.bp
# curl -s -o gLiveView.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/gLiveView.sh
# curl -s -o env https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/env
# chmod 755 gLiveView.sh

# sed -i env \
#     -e "s/\#CNODE_HOME=\"\/opt\/cardano\/cnode\"/CNODE_HOME=\"\$\{HOME\}\/node.bp\"/g" \
#     -e "s/CNODE_PORT=6000/CNODE_PORT=3000/g" \
#     -e "s/\#CONFIG=\"\${CNODE_HOME}\/files\/config.json\"/CONFIG=\"\${CNODE_HOME}\/config\/config.json\"/g" \
#     -e "s/\#SOCKET=\"\${CNODE_HOME}\/sockets\/node0.socket\"/SOCKET=\"\${CNODE_HOME}\/socket\/node.socket\"/g" \
#     -e "s/\#TOPOLOGY=\"\${CNODE_HOME}\/files\/topology.json\"/TOPOLOGY=\"\${CNODE_HOME}\/config\/topology.json\"/g" \
#     -e "s/\#LOG_DIR=\"\${CNODE_HOME}\/logs\"/LOG_DIR=\"\${CNODE_HOME}\/logs\"/g" \
#     -e "s/\#DB_DIR=\"\${CNODE_HOME}\/db\"/DB_DIR=\"\${CNODE_HOME}\/db\"/g"