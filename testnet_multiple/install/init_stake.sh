#!/bin/bash
# Beware this script requires some parts to be run in an air-gapped environment.
# Failure to do so will prevent the script from running.

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology

# importing utility functions
source $NS_PATH/utils.sh

echo
echo '---------------- Reading pool topology file and preparing a few things... ----------------'

read ERROR NODE_TYPE RELAYS < <(get_topo $TOPO_FILE)
RELAYS=($RELAYS)
cnt=${#RELAYS[@]}
let cnt1="$cnt/2"
let cnt2="$cnt - $cnt1"
RELAY_IPS=( "${RELAYS[@]:0:$cnt1}" )
RELAY_NAMES=( "${RELAYS[@]:$cnt1:$cnt2}" )

if [[ $ERROR == "none" ]]; then
    echo "NODE_TYPE: $NODE_TYPE"
    echo "RELAY_IPS: ${RELAY_IPS[@]}"
    echo "RELAY_NAMES: ${RELAY_NAMES[@]}"
else
    echo "ERROR: $ERROR"
    exit 1
fi

# checking we're in an air-gapped environment
if ping -q -c 1 -W 1 google.com >/dev/null; then
  echo "The network is up"
else
  echo "The network is down"
fi

IS_AIR_GAPPED=$(check_air_gap)

if [[ $IS_AIR_GAPPED == 1 ]]; then
    echo "we are air-gapped"
else
    echo "we are online"
fi

# getting the script state ready
STATE_FILE="$HOME/spot.state"

if [ -f "$STATE_FILE" ]; then
    # Source the state file to restore state
    . "$STATE_FILE" 2>/dev/null || :
else
    touch $STATE_FILE
    STATE_STEP_ID=0
    STATE_LAST_DATE="never"
    save_state STATE_STEP_ID STATE_LAST_DATE
fi

print_state $STATE_STEP_ID $STATE_LAST_DATE

echo
echo '---------------- Generating payment and stake keys / addresses ----------------'

if [[ $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 0 ]]; then
    echo "Install state, script: init_stake, step: $STATE_STEP_ID, generating payment key and stake key/address:"
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
    --testnet-magic 1097911063

    chmod 400 stake.addr

    # generate payment address which will delegate to the stake address
    cardano-cli address build \
    --payment-verification-key-file payment.vkey \
    --stake-verification-key-file stake.vkey \
    --out-file paymentwithstake.addr \
    --testnet-magic 1097911063

    chmod 400 paymentwithstake.addr

    # here you should fund paymentwithstake.addr with some ADA

    # generate a stake address registration certificate
    cardano-cli stake-address registration-certificate \
    --stake-verification-key-file stake.vkey \
    --out-file stake.cert

    chmod 400 stake.cert

    STATE_STEP_ID=1
    STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
    save_state STATE_STEP_ID STATE_LAST_DATE

    # make sure path to usb key is set as a global variable and add it to .bashrc
    if [[ -z "$SPOT_USB_KEY" ]]; then
        read -p "Enter path to usb key directory to be used to move data between offline and online environments: " SPOT_USB_KEY
    
        # add it to .bashrc
        echo $"if [[ -z \$SPOT_USB_KEY ]]; then
    export SPOT_USB_KEY=$SPOT_USB_KEY
fi" >> ~/.bashrc
        eval "$(cat ~/.bashrc | tail -n +10)"
        echo "\$SPOT_USB_KEY After: $SPOT_USB_KEY"
    fi

    # copy certain files to usb key to continue operations on bp node
    cp $STATE_FILE $SPOT_USB_KEY
    cp $HOME/keys/paymentwithstake.addr $SPOT_USB_KEY
    STATE_APPLY_SCRIPT=$SPOT_USB_KEY/apply_state.sh
    echo "#!/bin/bash
mkdir -p $HOME/keys
mv paymentwithstake.addr $HOME/keys
mv spot.state $HOME
echo \"state applied, please now run init_stake.sh\"" >> $STATE_APPLY_SCRIPT

else
    if [[ $IS_AIR_GAPPED == 0 ]]; then
        echo "[Install State] script: init_stake, step: $STATE_STEP_ID, generating payment key and stake key/address"
        echo "Error: cannot proceed, the environment is not air gapped."
        exit 1
    fi
fi

echo
echo "Now copy all files in $SPOT_USB_KEY to your bp node home folder and run apply_state.sh, then come back to this prompt..."

NEXT_STEP_OK=0
while [ "$NEXT_STEP_OK" -eq 0 ]; do
    read -p "Press enter to continue"
    # load state
    . "$STATE_FILE" 2>/dev/null || :
    print_state $STATE_STEP_ID $STATE_LAST_DATE

    if [[ $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 2 ]]; then
        $NEXT_STEP_OK=1
    elif [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 1 ]]; then
        $NEXT_STEP_OK=1
    fi
done

echo
echo '---------------- Registering staking adddress ----------------'

if [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 1 ]]; then
    # retrieve the stake address deposit parameter
    STAKE_ADDRESS_DEPOSIT=$(cardano-cli query protocol-parameters --testnet-magic 1097911063 | jq -r '.stakeAddressDeposit')
    echo "STAKE_ADDRESS_DEPOSIT: $STAKE_ADDRESS_DEPOSIT"

    # create a transaction to register our staking address onto the blockchain
    $NS_PATH/create_transaction.sh $(cat paymentwithstake.addr) $(cat paymentwithstake.addr) $STAKE_ADDRESS_DEPOSIT $HOME/keys/payment.skey $HOME/keys/stake.skey $HOME/keys/stake.cert
elif [[ $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 2 ]]; then
    echo "todo"
fi