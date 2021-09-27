#!/bin/bash

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

# importing utility functions
source $NS_PATH/utils.sh

if [[ $# -eq 1 && ! $1 == "" ]]; then nodeName=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 \"{versionTag}\""; exit 2; fi

sudo unattended-upgrade -d
sudo apt-get update -y
sudo apt-get upgrade -y

cardano-cli --version

echo
echo '---------------- Updating the node from source ---------------- '
cd ~/download/cardano-node
git fetch --all --tags
git checkout "tags/$1"

git describe --tags

if ! promptyn "Is this the correct tag? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

cabal clean
cabal update
cabal build all

cp -p "$($SPOT_PATH/scripts/bin_path.sh cardano-cli)" ~/.local/bin/
cp -p "$($SPOT_PATH/scripts/bin_path.sh cardano-node)" ~/.local/bin/
cardano-cli --version