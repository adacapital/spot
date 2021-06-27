#!/bin/bash
# In a real life scenario (MAINNET), you need to have your keys under cold storage.
# We're ok here as we're only playing with TESTNET.

# global variables
now=`date +"%Y%m%d_%H%M%S"`
NS_PATH="$HOME/stake-pool-tools/node-scripts"

echo
echo '---------------- Generating payment and stake keys / addresses ----------------'

cd $HOME
mkdir -p pool_keys
cd pool_keys

echo
echo '---------------- Generating cold key pair and cold counter certificate ----------------'

cardano-cli node key-gen \
--cold-verification-key-file cold.vkey \
--cold-signing-key-file cold.skey \
--operational-certificate-issue-counter-file cold.counter

echo
echo '---------------- Generating VRF key pair ----------------'

cardano-cli node key-gen-VRF \
--verification-key-file vrf.vkey \
--signing-key-file vrf.skey

echo
echo '---------------- Generating KES key pair ----------------'

cardano-cli node key-gen-KES \
--verification-key-file kes.vkey \
--signing-key-file kes.skey

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
echo '---------------- Moving cold keys to secure storage ----------------'