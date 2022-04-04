#!/bin/bash
# In a real life scenario (MAINNET), you need to have your keys under cold storage.
# We're ok here as we're only playing with TESTNET.

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
TOPO_FILE=~/pool_topology
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

echo "UPDATE POOL REGISTRATION STARTING..."
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "NS_PATH: $NS_PATH"

# importing utility functions
source $NS_PATH/utils.sh

cd $HOME/pool_keys

echo
echo '---------------- Create a JSON file with you testnet pool metadata ----------------'
# use a url you control (e.g. through your pool's website)
# here we will be using a gist in github (make sure the url is less than 65 character long, shorten it with git.io)
# example: https://gist.githubusercontent.com/adacapital/54d432465f85417e3793b89fd16539f3/raw/68eca2ca75dcafe48976d1dfa5bf7f06eda08c1f/adak_testnet.json becomes https://git.io/J3SYo
GIST_FILE_NAME="adact_testnet.json"
URL_TO_RAW_GIST_FILE="https://gist.githubusercontent.com/adacapital/84f98fce3e58096cf3feceaf202cba17/raw/e8dfd21b9be1be9c3e63b22b683cb41900974ecc/$GIST_FILE_NAME"
META_URL="https://git.io/J16cF"

echo "URL_TO_RAW_GIST_FILE: $URL_TO_RAW_GIST_FILE"

# if metadata json file exists archive it
if [ -f "$GIST_FILE_NAME" ]; then
    echo "Found old $GIST_FILE_NAME, moved it to $GIST_FILE_NAME.$NOW"
    mv $GIST_FILE_NAME $GIST_FILE_NAME.$NOW
fi

# download the file from gist
wget $URL_TO_RAW_GIST_FILE
# create a hash of your metadata file
META_DATA_HASH="$(cardano-cli stake-pool metadata-hash --pool-metadata-file $GIST_FILE_NAME)"
echo "META_DATA_HASH: $META_DATA_HASH"

echo
echo '---------------- Create a stake pool registration certificate ----------------'

POOL_PLEDGE=$(prompt_input_default POOL_PLEDGE 1000000000)
MIN_POOL_COST=$(cat $HOME/node.bp/config/sgenesis.json | jq -r '.protocolParams | .minPoolCost')
POOL_COST=$(prompt_input_default POOL_COST $MIN_POOL_COST)
POOL_MARGIN=$(prompt_input_default POOL_MARGIN 0.03)

echo
echo "Creating a registration certificate with the following parameters:"
echo "POOL_PLEDGE: $POOL_PLEDGE"
echo "POOL_COST: $POOL_COST"
echo "POOL_MARGIN: $POOL_MARGIN"
echo "META_URL: $META_URL"
echo "META_DATA_HASH: $META_DATA_HASH"
if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

cardano-cli stake-pool registration-certificate \
--cold-verification-key-file cold.vkey \
--vrf-verification-key-file vrf.vkey \
--pool-pledge $POOL_PLEDGE \
--pool-cost $POOL_COST \
--pool-margin $POOL_MARGIN \
--pool-reward-account-verification-key-file $HOME/keys/stake.vkey \
--pool-owner-stake-verification-key-file $HOME/keys/stake.vkey \
--testnet-magic 1097911063 \
--pool-relay-ipv4 51.104.251.142 \
--pool-relay-port 3001 \
--metadata-url $META_URL \
--metadata-hash $META_DATA_HASH \
--out-file pool-registration.cert

echo
echo '---------------- Create a delegation certificate ----------------'

cardano-cli stake-address delegation-certificate \
--stake-verification-key-file $HOME/keys/stake.vkey \
--cold-verification-key-file $HOME/cold_keys/cold.vkey \
--out-file delegation.cert

echo
echo '---------------- Submit stake pool registration certificate and delegation certificate to the blockchain ----------------'

# create a transaction to register our stake pool registration & delegation certificates onto the blockchain
$NS_PATH/create_transaction.sh $(cat $HOME/keys/paymentwithstake.addr) $(cat $HOME/keys/paymentwithstake.addr) 0 $HOME/keys/payment.skey $HOME/keys/stake.skey $HOME/pool_keys/cold.skey $HOME/pool_keys/pool-registration.cert $HOME/pool_keys/delegation.cert

# checking that our pool registration was successful
$NS_PATH/pool_info.sh