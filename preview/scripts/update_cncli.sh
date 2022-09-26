#!/bin/bash
# Only relevant for block producing node

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology

# importing utility functions
source $NS_PATH/utils.sh

CNCLI_PATH=`which cncli`
if [[ $CNCLI_PATH == "" ]]; then
    echo "CNCLI does not seem to be installed. Please run init_cncli first."
    exit 1
fi

CNCLI_VERSION=`cncli --version | head -1 | awk '{print $2}'`
RELEASETAG=$(curl -s https://api.github.com/repos/cardano-community/cncli/releases/latest | jq -r .tag_name)
VERSION=$(echo ${RELEASETAG} | cut -c 2-)

if [[ $CNCLI_VERSION < $RELEASETAG ]]; then
    echo "A newer version of CNCLI is available."

    if ! promptyn "Please confirm you want to install version $RELEASETAG? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi
fi
echo
echo '---------------- Installing CNCLI binary ----------------'

sudo systemctl stop cncli_sync.service

echo "Installing CNCLI binary release ${RELEASETAG}"
mkdir -p $HOME/download/cncli
curl -sLJ https://github.com/cardano-community/cncli/releases/download/${RELEASETAG}/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -o $HOME/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz

sudo tar xzvf $HOME/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -C /usr/local/bin/

echo "Checking installed version:"
cncli --version

sudo systemctl daemon-reload
sudo systemctl start cncli_sync.service