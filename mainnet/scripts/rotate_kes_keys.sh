#!/bin/bash
# Beware this script requires some parts to be run in an air-gapped environment.
# Failure to do so will prevent the script from running.

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=$ROOT_PATH/pool_topology

echo "ROTATE KES KEYS STARTING..."
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "ROOT_PATH: $ROOT_PATH"
echo "NS_PATH: $NS_PATH"
echo "TOPO_FILE: $TOPO_FILE"

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
STATE_FILE="$ROOT_PATH/spot.state"

if [ -f "$STATE_FILE" ]; then
    # Source the state file to restore state
    . "$STATE_FILE" 2>/dev/null || :

    if [[ $STATE_STEP_ID == 1 && $STATE_SUB_STEP_ID != "completed.trans" ]]; then
        echo
        print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR
        echo
        echo "State file is not as expected. Make sure to complete successfuly the init_stake step first."
        echo "Bye for now."
        exit 1
    elif [[ $STATE_STEP_ID == 2 && $STATE_SUB_STEP_ID == "cold.keys" ]]; then
        if [[ $NODE_TYPE != "airgap" || $IS_AIR_GAPPED == 0 ]]; then
            echo "Warning, to proceed further your environment must be air-gapped."
            echo "Bye for now!"
            exit 1
        fi
    elif [[ $STATE_STEP_ID == 4 && $STATE_SUB_STEP_ID == "rotate_kes_keys_opcert_gen" ]]; then
        if [[ $NODE_TYPE != "airgap" || $IS_AIR_GAPPED == 0 ]]; then
            echo "Warning, to proceed further your environment must be air-gapped."
            echo "Bye for now!"
            exit 1
        fi
    else
        STATE_STEP_ID=4
        STATE_SUB_STEP_ID="rotate_kes_keys_init"
        STATE_LAST_DATE="never"
        STATE_TRANS_WORK_DIR=""
    fi
else
    touch $STATE_FILE
    STATE_STEP_ID=4
    STATE_SUB_STEP_ID="rotate_kes_keys_init"
    STATE_LAST_DATE="never"
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE
fi

print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE

if [[ $NODE_TYPE == "bp" && $IS_AIR_GAPPED == 0 && $STATE_STEP_ID == 4 && $STATE_SUB_STEP_ID == "rotate_kes_keys_init" ]]; then
    cd $ROOT_PATH
    mkdir -p pool_keys
    cd pool_keys

    if [ -f "$ROOT_PATH/pool_keys/kes.skey" ]; then
        echo
        echo '---------------- Backing up previous KES key pair ----------------'
        chmod 664 $ROOT_PATH/pool_keys/kes.skey
        mv $ROOT_PATH/pool_keys/kes.skey $ROOT_PATH/pool_keys/kes.skey.$NOW
        chmod 400 $ROOT_PATH/pool_keys/kes.skey.$NOW
    fi

    if [ -f "$ROOT_PATH/pool_keys/node.cert" ]; then
        echo
        echo '---------------- Backing up previous operational certificate ----------------'
        chmod 664 $ROOT_PATH/pool_keys/node.cert
        mv $ROOT_PATH/pool_keys/node.cert $ROOT_PATH/pool_keys/node.cert.$NOW
        chmod 400 $ROOT_PATH/pool_keys/node.cert.$NOW
    fi

    echo
    echo '---------------- Generating KES key pair ----------------'

    cardano-cli node key-gen-KES \
    --verification-key-file kes.vkey \
    --signing-key-file kes.skey

    chmod 400 kes.skey

    echo
    echo '---------------- Gathering some information to generate the operational certificate ----------------'

    SLOTSPERKESPERIOD=$(cat $ROOT_PATH/node.bp/config/sgenesis.json | jq -r '.slotsPerKESPeriod')
    CTIP=$(cardano-cli query tip --mainnet | jq -r .slot)
    KES_PERIOD=$(expr $CTIP / $SLOTSPERKESPERIOD)
    STATE_SUB_STEP_ID="rotate_kes_keys_opcert_gen"
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE SLOTSPERKESPERIOD CTIP KES_PERIOD

    echo "SLOTSPERKESPERIOD: $SLOTSPERKESPERIOD"
    echo "CTIP: $CTIP"
    echo "KES_PERIOD: $KES_PERIOD"

    # copy certain files back to the air-gapped environment to continue operation there
    STATE_APPLY_SCRIPT=$ROOT_PATH/apply_state.sh
    echo
    echo "Please move the following files back to your air-gapped environment in your home directory and run apply_state.sh."
    echo $STATE_FILE
    echo $ROOT_PATH/pool_keys/kes.vkey
    echo $STATE_APPLY_SCRIPT

    echo '#!/bin/bash
ROOT_PATH="$(realpath "$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")")"
echo
echo '---------------- Backing up previous KES key pair ----------------'
chmod 664 $ROOT_PATH/pool_keys/kes.vkey
mv $ROOT_PATH/pool_keys/kes.vkey $ROOT_PATH/pool_keys/kes.vkey.$NOW
chmod 400 $ROOT_PATH/pool_keys/kes.vkey.$NOW
echo '---------------- Backing up previous operational certificate ----------------'
chmod 664 $ROOT_PATH/pool_keys/node.cert
mv $ROOT_PATH/pool_keys/node.cert $ROOT_PATH/pool_keys/node.cert.$NOW
chmod 400 $ROOT_PATH/pool_keys/node.cert.$NOW
mv kes.vkey $ROOT_PATH/pool_keys
chmod 400 $ROOT_PATH/pool_keys/kes.vkey
echo "state applied, please now run rotate_kes_keys.sh"' > $STATE_APPLY_SCRIPT
fi

if [[ $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 && $STATE_STEP_ID == 4 && $STATE_SUB_STEP_ID == "rotate_kes_keys_opcert_gen" ]]; then
    cd $ROOT_PATH
    mkdir -p pool_keys
    cd pool_keys

    echo
    echo '---------------- Generating the operational certificate ----------------'

    cardano-cli node issue-op-cert \
    --kes-verification-key-file $ROOT_PATH/pool_keys/kes.vkey \
    --cold-signing-key-file $ROOT_PATH/cold_keys/cold.skey \
    --operational-certificate-issue-counter $ROOT_PATH/cold_keys/cold.counter \
    --kes-period $KES_PERIOD \
    --out-file node.cert

    STATE_SUB_STEP_ID="rotate_kes_keys_opcert_install"
    STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE

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
    cp $ROOT_PATH/pool_keys/node.cert $SPOT_USB_KEY
    STATE_APPLY_SCRIPT=$SPOT_USB_KEY/apply_state.sh
    echo '#!/bin/bash
ROOT_PATH="$(realpath "$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")")"
mkdir -p $ROOT_PATH/pool_keys
mv node.cert $ROOT_PATH/pool_keys
chmod 400 $ROOT_PATH/pool_keys/node.cert
echo
echo '---------------- Restarting bp node ----------------'
sudo systemctl restart run.bp
echo \"New KES keys installed and bp node restarted. Until next time...\"' > $STATE_APPLY_SCRIPT

    echo
    echo "Now copy all files in $SPOT_USB_KEY to your bp node home folder and run apply_state.sh."
fi