#!/bin/bash
# In a real life scenario (MAINNET), you need to have your keys under cold storage.
# We're ok here as we're only playing with TESTNET.

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
echo $NS_PATH

# importing utility functions
source $NS_PATH/utils.sh
MAGIC=$(get_network_magic)
echo "NETWORK_MAGIC: $MAGIC"

echo
echo '---------------- Generating payment and stake keys / addresses ----------------'

cd $HOME
mkdir -p keys
cd keys

# generate payment key pair
cardano-cli address key-gen \
--verification-key-file payment.vkey \
--signing-key-file payment.skey

chmod 400 payment.vkey payment.skey

# here you should fund payment.addr with some ADA

# generate stake address key pair
cardano-cli stake-address key-gen \
--verification-key-file stake.vkey \
--signing-key-file stake.skey

chmod 400 stake.vkey stake.skey

# generate stake address
cardano-cli stake-address build \
--stake-verification-key-file stake.vkey \
--out-file stake.addr \
--testnet-magic $MAGIC

chmod 400 stake.addr

# generate payment address which will delegate to the stake address
cardano-cli address build \
--payment-verification-key-file payment.vkey \
--stake-verification-key-file stake.vkey \
--out-file paymentwithstake.addr \
--testnet-magic $MAGIC

chmod 400 paymentwithstake.addr

# here you should fund paymentwithstake.addr with some ADA

# generate a stake address registration certificate
cardano-cli stake-address registration-certificate \
--stake-verification-key-file stake.vkey \
--out-file stake.cert

chmod 400 stake.cert

if ! promptyn "Please confirm paymentwithstake.addr is funded? (y/n)"; then
    echo "Please fund paymentwithstake.addr and run init_stake again."
    exit 1
fi

echo
echo '---------------- Registering staking adddress ----------------'

# retrieve the stake address deposit parameter
STAKE_ADDRESS_DEPOSIT=$(cardano-cli query protocol-parameters --testnet-magic $MAGIC | jq -r '.stakeAddressDeposit')
echo "STAKE_ADDRESS_DEPOSIT: $STAKE_ADDRESS_DEPOSIT"

# create a transaction to register our staking address onto the blockchain
$NS_PATH/create_transaction.sh $(cat paymentwithstake.addr) $(cat paymentwithstake.addr) $STAKE_ADDRESS_DEPOSIT $HOME/keys/payment.skey $HOME/keys/stake.skey $HOME/keys/stake.cert