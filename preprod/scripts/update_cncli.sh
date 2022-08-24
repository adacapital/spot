#!/bin/bash
# Only relevant for block producing node

# Installing CNCLI binary
RELEASETAG=$(curl -s https://api.github.com/repos/cardano-community/cncli/releases/latest | jq -r .tag_name)
VERSION=$(echo ${RELEASETAG} | cut -c 2-)
echo "Installing CNCLI binary release ${RELEASETAG}"

mkdir -p $HOME/download/cncli

curl -sLJ https://github.com/cardano-community/cncli/releases/download/${RELEASETAG}/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -o $HOME/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz

sudo tar xzvf $HOME/download/cncli/cncli-${VERSION}-x86_64-unknown-linux-gnu.tar.gz -C /usr/local/bin/

echo "Checking installed version:"
cncli -V