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
MAGIC=$(get_network_magic)
echo "NETWORK_MAGIC: $MAGIC"

exit 1

echo
echo '---------------- Reading pool topology file and preparing a few things... ----------------'

read ERROR NODE_TYPE BP_IP RELAYS < <(get_topo $TOPO_FILE)
RELAYS=($RELAYS)
cnt=${#RELAYS[@]}
let cnt1="$cnt/3"
let cnt2="$cnt1 + $cnt1"
let cnt3="$cnt2 + $cnt1"

RELAY_IPS=( "${RELAYS[@]:0:$cnt1}" )
RELAY_NAMES=( "${RELAYS[@]:$cnt1:$cnt1}" )
RELAY_IPS_PUB=( "${RELAYS[@]:$cnt2:$cnt1}" )

if [[ $ERROR == "none" ]]; then
    echo "NODE_TYPE: $NODE_TYPE"
    echo "RELAY_IPS: ${RELAY_IPS[@]}"
    echo "RELAY_NAMES: ${RELAY_NAMES[@]}"
    echo "RELAY_IPS_PUB: ${RELAY_IPS_PUB[@]}"
else
    echo "ERROR: $ERROR"
    exit 1
fi

IS_AIR_GAPPED=0
if [[ $NODE_TYPE == "airgap" ]]; then
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
fi

# getting the script state ready
STATE_FILE="$HOME/spot.state"

if [ -f "$STATE_FILE" ]; then
    # Source the state file to restore state
    . "$STATE_FILE" 2>/dev/null || :
else
    touch $STATE_FILE
    STATE_STEP_ID=0
    STATE_SUB_STEP_ID="init"
    STATE_LAST_DATE="never"
    STATE_TRANS_WORK_DIR=""
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR
fi

print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR


if [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 0 ]]; then
    echo
    echo '---------------- Generating payment and stake keys / addresses ----------------'

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

    STATE_STEP_ID=1
    STATE_SUB_STEP_ID="build.trans"
    STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR

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
    cp $HOME/keys/stake.cert $SPOT_USB_KEY
    STATE_APPLY_SCRIPT=$SPOT_USB_KEY/apply_state.sh
    echo "#!/bin/bash
mkdir -p $HOME/keys
mv paymentwithstake.addr $HOME/keys
mv stake.cert $HOME/keys
chmod 400 $HOME/keys/paymentwithstake.addr
chmod 400 $HOME/keys/stake.cert
echo \"state applied, please now run init_stake.sh\"" > $STATE_APPLY_SCRIPT

    echo
    echo "Now copy all files in $SPOT_USB_KEY to your bp node home folder and run apply_state.sh, then come back to this prompt..."
else
    if [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 0 ]]; then
        echo "[Install State] script: init_stake, step: $STATE_STEP_ID, generating payment key and stake key/address"
        echo "Error: cannot proceed, the environment is not air gapped."
        exit 1
    fi
fi

NEXT_STEP_OK=0
while [ "$NEXT_STEP_OK" -eq 0 ]; do
    read -p "Press enter to continue"
    # load state
    . "$STATE_FILE" 2>/dev/null || :
    print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR
    echo 

    if [[ $STATE_SUB_STEP_ID == "sign.trans" && $IS_AIR_GAPPED == 0 ]]; then
        echo "Warning, to proceed further your environment must be air-gapped."
    fi

    if [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 1 && $STATE_SUB_STEP_ID == "sign.trans" ]]; then
        NEXT_STEP_OK=1
    elif [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 1 && $STATE_SUB_STEP_ID == "build.trans" ]]; then
        NEXT_STEP_OK=1
    elif [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 1 && $STATE_SUB_STEP_ID == "submit.trans" ]]; then
        NEXT_STEP_OK=1
    fi
done

echo
echo '---------------- Registering staking adddress ----------------'

if [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 1 && $STATE_SUB_STEP_ID == "build.trans" ]]; then
    # retrieve the stake address deposit parameter
    STAKE_ADDRESS_DEPOSIT=$(cardano-cli query protocol-parameters --testnet-magic $MAGIC | jq -r '.stakeAddressDeposit')
    echo "STAKE_ADDRESS_DEPOSIT: $STAKE_ADDRESS_DEPOSIT"

    # making sure paymentwithstake.addr is funded
    echo "Please make sure paymentwithstake.addr ($(cat $HOME/keys/paymentwithstake.addr)) is funded with enough ADA to register your staking address."
    if ! promptyn "Please confirm you want to proceed? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    # creating and sending a transaction to register our staking address onto the blockchain
    $NS_PATH/create_transaction.sh $(cat $HOME/keys/paymentwithstake.addr) $(cat $HOME/keys/paymentwithstake.addr) $STAKE_ADDRESS_DEPOSIT NONE NONE $HOME/keys/stake.cert
elif [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 1 && $STATE_SUB_STEP_ID == "sign.trans" ]]; then
    # signing a transaction to register our staking address onto the blockchain
    $NS_PATH/create_transaction.sh NONE NONE NONE $HOME/keys/payment.skey $HOME/keys/stake.skey $HOME/keys/stake.cert
elif [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 1 && $STATE_SUB_STEP_ID == "submit.trans" ]]; then
    # submiting a transaction to register our staking address onto the blockchain
    $NS_PATH/create_transaction.sh NONE NONE NONE NONE NONE NONE
fi