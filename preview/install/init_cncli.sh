#!/bin/bash
# Only relevant for block producing node

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

# importing utility functions
source $NS_PATH/utils.sh
MAGIC=$(get_network_magic)
echo "NETWORK_MAGIC: $MAGIC"

# calculating the shelley hash
SHELLEY_GENESIS_HASH=$(cardano-cli genesis hash --genesis ~/node.bp/config/sgenesis.json)

# Installing CNCLI binary
RELEASETAG=$(curl -s https://api.github.com/repos/cardano-community/cncli/releases/latest | jq -r .tag_name)
VERSION=$(echo ${RELEASETAG} | cut -c 2-)
echo "Installing CNCLI binary release ${RELEASETAG}"
mkdir -p $HOME/download/cncli
curl -sLJ https://github.com/cardano-community/cncli/releases/download/${RELEASETAG}/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -o $HOME/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz

sudo tar xzvf $HOME/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -C /usr/local/bin/

echo "Checking installed version:"
cncli -V

echo "Setting up CNCLI SYNC as a service"
BLOCKPRODUCING_IP="127.0.0.1"
BLOCKPRODUCING_PORT=3000

mkdir -p $HOME/node.bp/cncli

cat > $HOME/node.bp/cncli/cncli_sync.service << EOF
[Unit]
Description=CNCLI Sync
After=multi-user.target

[Service]
User=$USER
Type=simple
Restart=always
RestartSec=5
LimitNOFILE=131072
ExecStart=/usr/local/bin/cncli sync --network-magic $MAGIC --host $BLOCKPRODUCING_IP --port $BLOCKPRODUCING_PORT --db $HOME/node.bp/cncli/cncli.db --shelley-genesis-hash $SHELLEY_GENESIS_HASH
KillSignal=SIGINT
SuccessExitStatus=143
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=cncli_sync

[Install]
WantedBy=multi-user.target
EOF

sudo mv $HOME/node.bp/cncli/cncli_sync.service /etc/systemd/system/cncli_sync.service

sudo systemctl daemon-reload
sudo systemctl enable cncli_sync
sudo systemctl start cncli_sync.service

# note cncli service logs can be seen in /var/log/syslog