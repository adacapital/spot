#!/bin/bash
# Beware this script requires some parts to be run in an air-gapped environment.
# Failure to do so will prevent the script from running.

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

    if [[ $STATE_STEP_ID == 2 && $STATE_SUB_STEP_ID != "completed" ]]; then
        echo
        print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR
        echo
        echo "State file is not as expected. Make sure to complete successfuly the init_pool step first."
        echo "Bye for now."
        exit 1
    elif [[ $STATE_STEP_ID == 2 && $STATE_SUB_STEP_ID == "completed" ]]; then
        STATE_STEP_ID=3
        STATE_SUB_STEP_ID="init"
        STATE_LAST_DATE="never"
        STATE_TRANS_WORK_DIR=""
    elif [[ $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "certificates" ]]; then
        if [[ $NODE_TYPE != "airgap" || $IS_AIR_GAPPED == 0 ]]; then
            echo "Warning, to proceed further your environment must be air-gapped."
            echo "Bye for now!"
            exit 1
        fi
    fi

else
    touch $STATE_FILE
    STATE_STEP_ID=3
    STATE_SUB_STEP_ID="init"
    STATE_LAST_DATE="never"
    STATE_TRANS_WORK_DIR=""
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR
fi

print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR $META_URL $META_DATA_HASH $MIN_POOL_COST

cd $HOME/pool_keys

if [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "init" ]]; then
    echo
    echo '---------------- Create a JSON file with you testnet pool metadata ----------------'
    # use a url you control (e.g. through your pool's website)
    # here we will be using a gist in github (make sure the url is less than 65 character long, shorten it with git.io)
    # example: https://gist.githubusercontent.com/adacapital/54d432465f85417e3793b89fd16539f3/raw/68eca2ca75dcafe48976d1dfa5bf7f06eda08c1f/adak_testnet.json becomes https://git.io/J3SYo
    GIST_FILE_NAME="adakt_testnet.json"
    URL_TO_RAW_GIST_FILE="https://gist.githubusercontent.com/adacapital/cf57f06ba57830df38e140dc5f67f50f/raw/283cca8932b07ae8fb5dee8b956b29a7ed66fcdf/$GIST_FILE_NAME"
    META_URL="https://git.io/JDsXg"

    GIST_FILE_NAME=$(prompt_input_default GIST_FILE_NAME $GIST_FILE_NAME)
    URL_TO_RAW_GIST_FILE=$(prompt_input_default URL_TO_RAW_GIST_FILE $URL_TO_RAW_GIST_FILE)
    META_URL=$(prompt_input_default META_URL $META_URL)

    echo
    echo "Details of your gist file containing the metadata to be used for your pool registration certificate:"
    echo "GIST_FILE_NAME: $GIST_FILE_NAME"
    echo "URL_TO_RAW_GIST_FILE: $URL_TO_RAW_GIST_FILE"
    echo "META_URL: $META_URL"
    if ! promptyn "Please confirm you want to proceed? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    # download the file from gist
    wget $URL_TO_RAW_GIST_FILE
    # create a hash of your metadata file
    META_DATA_HASH="$(cardano-cli stake-pool metadata-hash --pool-metadata-file $GIST_FILE_NAME)"
    echo "META_DATA_HASH: $META_DATA_HASH"

    # getting useful information for next step
    MIN_POOL_COST=$(cat $HOME/node.bp/config/sgenesis.json | jq -r '.protocolParams | .minPoolCost')
    STATE_SUB_STEP_ID="certificates"
    STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR META_URL META_DATA_HASH MIN_POOL_COST

    # copy certain files back to the air-gapped environment to continue operation there
    STATE_APPLY_SCRIPT=$HOME/apply_state.sh
    echo
    echo "Please move the following files back to your air-gapped environment in your home directory and run register_pool.sh."
    echo $STATE_FILE
    echo
fi

if [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "certificates" ]]; then
    echo
    echo '---------------- Create a stake pool registration certificate ----------------'

    # preparing string with relays public ips and ports
    RELAYS_COUNT=${#RELAY_IPS_PUB[@]}
    RELAY_PARAMS=""
    for (( i=0; i<${RELAYS_COUNT}; i++ ));
    do
        RELAY_PARAMS+="--pool-relay-ipv4 ${RELAY_IPS_PUB[$i]} "
        RELAY_PARAMS+="--pool-relay-port 3001 "
    done

    POOL_PLEDGE=$(prompt_input_default POOL_PLEDGE 1000000000)
    POOL_COST=$(prompt_input_default POOL_COST $MIN_POOL_COST)
    POOL_MARGIN=$(prompt_input_default POOL_MARGIN 0.03)

    echo
    echo "Creating a registration certificate with the following parameters:"
    echo "POOL_PLEDGE: $POOL_PLEDGE"
    echo "POOL_COST: $POOL_COST"
    echo "POOL_MARGIN: $POOL_MARGIN"
    echo "META_URL: $META_URL"
    echo "META_DATA_HASH: $META_DATA_HASH"
    echo "RELAY_PARAMS: $RELAY_PARAMS"
    if ! promptyn "Please confirm you want to proceed? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    cardano-cli stake-pool registration-certificate \
    --cold-verification-key-file $HOME/cold_keys/cold.vkey \
    --vrf-verification-key-file $HOME/pool_keys/vrf.vkey \
    --pool-pledge $POOL_PLEDGE \
    --pool-cost $POOL_COST \
    --pool-margin $POOL_MARGIN \
    --pool-reward-account-verification-key-file $HOME/keys/stake.vkey \
    --pool-owner-stake-verification-key-file $HOME/keys/stake.vkey \
    --testnet-magic 1097911063 \
    $RELAY_PARAMS \
    --metadata-url $META_URL \
    --metadata-hash $META_DATA_HASH \
    --out-file pool-registration.cert

    echo
    echo '---------------- Create a delegation certificate ----------------'

    cardano-cli stake-address delegation-certificate \
    --stake-verification-key-file $HOME/keys/stake.vkey \
    --cold-verification-key-file $HOME/cold_keys/cold.vkey \
    --out-file delegation.cert

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
    cp $HOME/pool_keys/pool-registration.cert $SPOT_USB_KEY
    cp $HOME/pool_keys/delegation.cert $SPOT_USB_KEY
    STATE_APPLY_SCRIPT=$SPOT_USB_KEY/apply_state.sh
    echo "#!/bin/bash
mv pool-registration.cert \$HOME/pool_keys
mv delegation.cert \$HOME/pool_keys
chmod 400 \$HOME/pool_keys/pool-registration.cert
chmod 400 \$HOME/pool_keys/delegation.cert
echo \"state applied, please now run register_pool.sh\"" > $STATE_APPLY_SCRIPT

    echo
    echo "Now copy all files in $SPOT_USB_KEY to your bp node home folder and run apply_state.sh, then come back to this prompt..."
fi

NEXT_STEP_OK=0
while [ "$NEXT_STEP_OK" -eq 0 ]; do
    read -p "Press enter to continue"
    # load state
    . "$STATE_FILE" 2>/dev/null || :
    print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR $META_URL $META_DATA_HASH $MIN_POOL_COST
    echo 

    if [[ $STATE_SUB_STEP_ID == "sign.trans" && $IS_AIR_GAPPED == 0 ]]; then
        echo "Warning, to proceed further your environment must be air-gapped."
    fi

    if [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "sign.trans" ]]; then
        NEXT_STEP_OK=1
    elif [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "build.trans" ]]; then
        NEXT_STEP_OK=1
    elif [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "submit.trans" ]]; then
        NEXT_STEP_OK=1
    fi
done

echo
echo '---------------- Submit stake pool registration certificate and delegation certificate to the blockchain ----------------'

if [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "build.trans" ]]; then
    # create a transaction to register our stake pool registration & delegation certificates onto the blockchain
    $NS_PATH/create_transaction.sh $(cat $HOME/keys/paymentwithstake.addr) $(cat $HOME/keys/paymentwithstake.addr) 0 NONE NONE NONE $HOME/pool_keys/pool-registration.cert $HOME/pool_keys/delegation.cert
elif [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "sign.trans" ]]; then
    # signing a transaction to register our stake pool registration & delegation certificates onto the blockchain
    $NS_PATH/create_transaction.sh NONE NONE NONE $HOME/keys/payment.skey $HOME/keys/stake.skey $HOME/cold_keys/cold.skey NONE NONE
elif [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 3 && $STATE_SUB_STEP_ID == "submit.trans" ]]; then
    # submiting a transaction to register our stake pool registration & delegation certificates onto the blockchain
    $NS_PATH/create_transaction.sh NONE NONE NONE NONE NONE NONE
fi