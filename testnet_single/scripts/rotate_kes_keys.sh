#!/bin/bash
# In a real life scenario (MAINNET), you need to have your keys under cold storage.
# We're ok here as we're only playing with TESTNET.

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

cd $HOME
cd pool_keys

if [ -f "$HOME/pool_keys/kes.vkey" ]; then
    echo
    echo '---------------- Backing up previous KES key pair ----------------'
    chmod 664 $HOME/pool_keys/kes.vkey
    chmod 664 $HOME/pool_keys/kes.skey
    mv $HOME/pool_keys/kes.vkey $HOME/pool_keys/kes.vkey.$NOW
    mv $HOME/pool_keys/kes.skey $HOME/pool_keys/kes.skey.$NOW
    chmod 400 $HOME/pool_keys/kes.vkey.$NOW
    chmod 400 $HOME/pool_keys/kes.skey.$NOW
fi


if [ -f "$HOME/pool_keys/node.cert" ]; then
    echo
    echo '---------------- Backing up previous operational certificate ----------------'
    chmod 664 $HOME/pool_keys/node.cert
    mv $HOME/pool_keys/node.cert $HOME/pool_keys/node.cert.$NOW
    chmod 400 $HOME/pool_keys/node.cert.$NOW
fi


echo
echo '---------------- Generating KES key pair ----------------'

cardano-cli node key-gen-KES \
--verification-key-file kes.vkey \
--signing-key-file kes.skey

chmod 400 kes.skey

echo
echo '---------------- Generating the operational certificate ----------------'

SLOTSPERKESPERIOD=$(cat $HOME/node.bp/config/sgenesis.json | jq -r '.slotsPerKESPeriod')
CTIP=$(cardano-cli query tip --testnet-magic 1097911063 | jq -r .slot)
KES_PERIOD=$(expr $CTIP / $SLOTSPERKESPERIOD)
echo "SLOTSPERKESPERIOD: $SLOTSPERKESPERIOD"
echo "CTIP: $CTIP"
echo "KES_PERIOD: $KES_PERIOD"

cardano-cli node issue-op-cert \
--kes-verification-key-file kes.vkey \
--cold-signing-key-file cold.skey \
--operational-certificate-issue-counter cold.counter \
--kes-period $KES_PERIOD \
--out-file node.cert

echo
echo '---------------- Restarting bp node ----------------'

sudo systemctl restart run.bp