#!/bin/bash

if [[ $# -eq 1 && ! $1 == "" ]]; then nodeName=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {versionTag}"; exit 2; fi

sudo unattended-upgrade -d
sudo apt-get update -y
sudo apt-get upgrade -y

echo
echo '---------------- Updating the node from source ---------------- '
cd ~/download/cardano-node
git fetch --all --tags
git checkout "tags/$1"

cabal clean
cabal update
cabal build all

cp -p "$(./bin-path.sh cardano-cli)" ~/.local/bin/
cp -p "$(./bin-path.sh cardano-node)" ~/.local/bin/
cardano-cli --version