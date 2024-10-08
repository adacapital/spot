#!/bin/bash
# Beware, in a real life scenario (MAINNET), you need to have your keys under cold storage.
# Signing a transaction need to happen in your air-gapped environement.

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT1="$(realpath "$(dirname "$SPOT_DIR")")"
ROOT_PATH="$(realpath "$(dirname "$PARENT1")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=$ROOT_PATH/pool_topology

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "ROOT_PATH: $ROOT_PATH"
echo "NS_PATH: $NS_PATH"
echo "TOPO_FILE: $TOPO_FILE"

# importing utility functions
source $NS_PATH/utils.sh

# TODO: there are 2 prototypes expecting 6 params! :)
if [[ $# -eq 6 && ! $1 == "" && ! $2 == "" && ! $3 == "" && ! $4 == "" && ! $5 == ""  && ! $6 == "" ]]; then SOURCE_PAYMENT_ADDR=$1; DEST_PAYMENT_ADDR=""; LOVELACE_AMOUNT=0; SKEY_FILE=$2; SKEY_FILE_STAKE=""; STAKE_CERT_FILE=""; COLD_KEY_FILE=$3; COLD_VKEY_FILE=$4; POOL_CERT_FILE=""; DELEGATION_CERT_FILE=""; VOTE_METADATA_JSON=$5; COLD_VKEY_HASH=$6;
elif [[ $# -eq 4 && ! $1 == "" && ! $2 == "" && ! $3 == "" && ! $4 == "" ]]; then SOURCE_PAYMENT_ADDR=$1; DEST_PAYMENT_ADDR=$2; LOVELACE_AMOUNT=$3; SKEY_FILE=$4; SKEY_FILE_STAKE=""; STAKE_CERT_FILE=""; COLD_KEY_FILE=""; POOL_CERT_FILE=""; DELEGATION_CERT_FILE="";
elif [[ $# -eq 6 && ! $1 == "" && ! $2 == "" && ! $3 == "" && ! $4 == "" && ! $5 == "" && ! $6 == "" ]]; then SOURCE_PAYMENT_ADDR=$1; DEST_PAYMENT_ADDR=$2; LOVELACE_AMOUNT=$3; SKEY_FILE=$4; SKEY_FILE_STAKE=$5; STAKE_CERT_FILE=$6; COLD_KEY_FILE=""; POOL_CERT_FILE=""; DELEGATION_CERT_FILE="";
elif [[ $# -eq 8 && ! $1 == "" && ! $2 == "" && ! $3 == "" && ! $4 == "" && ! $5 == "" && ! $6 == "" && ! $7 == "" && ! $8 == "" ]]; then SOURCE_PAYMENT_ADDR=$1; DEST_PAYMENT_ADDR=$2; LOVELACE_AMOUNT=$3; SKEY_FILE=$4; SKEY_FILE_STAKE=$5; COLD_KEY_FILE=$6; POOL_CERT_FILE=$7; DELEGATION_CERT_FILE=$8; STAKE_CERT_FILE="";
else 
    echo -e "This script requires input parameters:\n\tUsages:"
    echo -e "\t\t$0 {source_payment_addr} {pay sign key file} {pool cold vkey file} {pool cold skey file} {vote metadata json file} {pool cold.vkey hash}"
    echo -e "\t\t$0 {source_payment_addr} {dest_payment_addr} {lovelace}"
    echo -e "\t\t$0 {source_payment_addr} {dest_payment_addr} {lovelace} {sign key file}"
    echo -e "\t\t$0 {source_payment_addr} {dest_payment_addr} {lovelace} {sign key file} {stake sign key file} {stake certificate file}"
    echo -e "\t\t$0 {source_payment_addr} {dest_payment_addr} {lovelace} {sign key file} {stake sign key file} {cold key file} {pool certificate file} {delegation certificate file}"
    exit 2
fi

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
else
    echo "ERROR: $ERROR"
    exit 1
fi

NODE_PATH="$ROOT_PATH/node.bp"
echo "NODE_PATH: $NODE_PATH"

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
else
    touch $STATE_FILE
    STATE_STEP_ID=0
    STATE_SUB_STEP_ID="build.trans"
    STATE_LAST_DATE="never"
    STATE_TRANS_WORK_DIR=""
    save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR
fi

print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR

if [[ $STATE_SUB_STEP_ID == "build.trans" && $IS_AIR_GAPPED == 0 ]]; then
    echo
    echo '---------------- Preparing the transaction... ----------------'

    # starting the transaction process itself
    echo
    echo -e "Sending:\t\t$LOVELACE_AMOUNT lovelace"
    echo -e "From address:\t\t$SOURCE_PAYMENT_ADDR"
    echo -e "To address:\t\t$DEST_PAYMENT_ADDR"
    if [[ $SKEY_FILE != "" ]]; then echo -e "Sign key file:\t\t$SKEY_FILE"; fi
    if [[ $SKEY_FILE_STAKE != "" ]]; then echo -e "Sign key file stake:\t$SKEY_FILE_STAKE"; fi
    if [[ $STAKE_CERT_FILE != "" ]]; then echo -e "Certificate file:\t$STAKE_CERT_FILE"; fi
    if [[ $COLD_KEY_FILE != "" ]]; then echo -e "Cold Key file:\t$COLD_KEY_FILE"; fi
    if [[ $POOL_CERT_FILE != "" ]]; then echo -e "Pool certificate file:\t$POOL_CERT_FILE"; fi
    if [[ $DELEGATION_CERT_FILE != "" ]]; then echo -e "Delegation certificate file:\t$DELEGATION_CERT_FILE"; fi
    if [[ $VOTE_METADATA_JSON != "" ]]; then echo -e "Vote metadata json file:\t$VOTE_METADATA_JSON"; fi
    if ! promptyn "Please confirm you want to proceed? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi

    # create working directory for the transaction
    mkdir -p $ROOT_PATH/transactions
    cd $ROOT_PATH/transactions
    mkdir $NOW
    cd $NOW
    CUR_DIR=`pwd`

    # get protocol parameters
    cardano-cli query protocol-parameters --mainnet --out-file protocol.json

    # determine the TTL (Time To Live) for the transaction
    # CTIP : the current tip of the blockchain
    CTIP=$(cardano-cli query tip --mainnet | jq -r .slot)
    TTL=$(expr $CTIP + 1200)

    echo "CTIP: $CTIP"
    echo "TTL: $TTL"

    # get utx0 details of SOURCE_PAYMENT_ADDR
    UTXO_RAW=$($NS_PATH/query_payment_addr.sh $SOURCE_PAYMENT_ADDR > query_payment_addr.out) 

    tail -n +3 query_payment_addr.out | sort -k3 -nr > utxos.out

    echo "Source payment address UTXOs:"
    cat utxos.out
    rm -f assets.out
    touch assets.out

    TX_IN=""
    TOTAL_BALANCE=0
    TOTAL_ASSETS=""
    while read -r UTXO; do
        UTXO_HASH=$(awk '{ print $1 }' <<< "${UTXO}")
        UTXO_TXIX=$(awk '{ print $2 }' <<< "${UTXO}")
        UTXO_BALANCE=$(awk '{ print $3 }' <<< "${UTXO}")
        UTXO_ASSETS=$(awk -F'lovelace' '{print $2}' <<< "${UTXO}")
        if [[ ! $UTXO_ASSETS == " + TxOutDatumNone" ]]; then
            # UTXO_ASSETS="toto"
            SPLITTED="$(sed "s/ + /\n/g" <<< "$UTXO_ASSETS")"
            readarray -t ARRAY <<< "$SPLITTED"

            if [[ ${#ARRAY[@]} -gt 2 ]]; then
                for a in "${ARRAY[@]}"; do
                    if [[ ! $a == "" && ! $a == "TxOutDatumNone" ]]; then
                        # echo "> '$a'"
                        ASSET_AMOUNT=$(awk '{ print $1 }' <<< "$a")
                        ASSET_POLICY=$(awk '{ print $2 }' <<< "$a")
                        echo "{\"amount\": $ASSET_AMOUNT, \"policy\": \"$ASSET_POLICY\"}" >> assets.out
                    fi
                done
            fi
        else
            UTXO_ASSETS=""
        fi
        TOTAL_BALANCE=$((${TOTAL_BALANCE}+${UTXO_BALANCE}))
        echo "TxIn: ${UTXO_HASH}#${UTXO_TXIX}"
        echo "Lovelace: ${UTXO_BALANCE}"
        echo "Assets: ${UTXO_ASSETS}"
        TX_IN="${TX_IN} --tx-in ${UTXO_HASH}#${UTXO_TXIX}"
    done < utxos.out
    TXCNT=$(cat utxos.out | wc -l)
    echo "Total lovelace balance: $TOTAL_BALANCE"
    echo "UTXO count: $TXCNT"
    echo "TX_IN: $TX_IN"

    cat assets.out | jq -s 'group_by(.policy) | map({policy: .[0].policy, amount: map(.amount) | add})' | jq -r '.[] | "\(.amount)\t\(.policy)"' > assets2.out
    while read -r ASSET; do
        ASSET_AMOUNT=$(awk '{ print $1 }' <<< "$ASSET")
        ASSET_POLICY=$(awk '{ print $2 }' <<< "$ASSET")
        if [[ ! $TOTAL_ASSETS == "" ]]; then
            TOTAL_ASSETS="${TOTAL_ASSETS} + "
        fi
        TOTAL_ASSETS="${TOTAL_ASSETS}${ASSET_AMOUNT} ${ASSET_POLICY}"
    done < assets2.out
    echo "TOTAL_ASSETS: ${TOTAL_ASSETS}"

    if [[ $TX_IN == "" ]]; then
        echo "ERROR: Cannot create transaction, Empty UTXO in SOURCE_PAYMENT_ADDR: $SOURCE_PAYMENT_ADDR"
        echo "Ok bye!"
        exit 1
    fi

    # calculate the number of output to the transaction
    TXOCNT=2
    if [[ $DEST_PAYMENT_ADDR == $SOURCE_PAYMENT_ADDR ]]; then TXOCNT=1; fi
    if [[ $VOTE_METADATA_JSON != "" ]]; then TXOCNT=1; fi

    # calculate the number of witness to the transaction
    WITCNT=1
    if [[ $STAKE_CERT_FILE != "" ]]; then WITCNT=2; fi
    if [[ $VOTE_METADATA_JSON != "" ]]; then WITCNT=2; fi
    if [[ $DELEGATION_CERT_FILE != "" ]]; then WITCNT=3; fi

    echo "TXOCNT: $TXOCNT"
    echo "WITCNT: $WITCNT"

    # draft the transaction
    if [[ $TXOCNT -eq 1 ]]; then
        if [[ $STAKE_CERT_FILE == "" && $DELEGATION_CERT_FILE == "" && $VOTE_METADATA_JSON == "" ]]; then
            echo "Creating a draft standard transaction with 1 output"

            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $DEST_PAYMENT_ADDR+0 \
            --ttl 0 \
            --fee 0 \
            --out-file tx.raw.draft
        elif [[ $STAKE_CERT_FILE != "" ]]; then
            echo "Creating a draft stake address registration transaction"

            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $DEST_PAYMENT_ADDR+0 \
            --ttl 0 \
            --fee 0 \
            --out-file tx.raw.draft \
            --certificate-file $STAKE_CERT_FILE
        elif [[ $DELEGATION_CERT_FILE != "" ]]; then
            echo "Creating a draft stake pool registration transaction"

            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $DEST_PAYMENT_ADDR+0 \
            --ttl 0 \
            --fee 0 \
            --out-file tx.raw.draft \
            --certificate-file $POOL_CERT_FILE \
            --certificate-file $DELEGATION_CERT_FILE
        elif [[ $VOTE_METADATA_JSON != "" ]]; then
            echo "Creating a draft stake pool vote transaction"
            dummyRequiredHash="12345678901234567890123456789012345678901234567890123456"

            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $SOURCE_PAYMENT_ADDR+0 \
            --json-metadata-detailed-schema \
            --metadata-json-file $VOTE_METADATA_JSON \
            --ttl 0 \
            --fee 0 \
            --required-signer-hash ${dummyRequiredHash} \
            --out-file tx.raw.draft
        fi
    else
        echo "Creating a draft standard transaction with 2 outputs"

        cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $DEST_PAYMENT_ADDR+$LOVELACE_AMOUNT \
        --tx-out $SOURCE_PAYMENT_ADDR+0 \
        --ttl 0 \
        --fee 0 \
        --out-file tx.raw.draft
    fi

    # calculate the transaction fee and the final balance for SOURCE_PAYMENT_ADDR
    FEE_RAW=$(cardano-cli transaction calculate-min-fee \
    --tx-body-file tx.raw.draft \
    --tx-in-count ${TXCNT} \
    --tx-out-count ${TXOCNT} \
    --witness-count ${WITCNT} \
    --byron-witness-count 0 \
    --mainnet \
    --protocol-params-file protocol.json | awk '{print $1}')

    # Add 10,000 lovelace to the estimated fee
    FEE=$(expr $FEE_RAW + 10000)

    echo "TOTAL_BALANCE: ${TOTAL_BALANCE}"
    echo "LOVELACE_AMOUNT: ${LOVELACE_AMOUNT}"
    echo "FEE (raw): ${FEE_RAW}"
    echo "FEE (final): ${FEE}"


    UTXO_LOVELACE_BALANCE_FINAL=$(expr $TOTAL_BALANCE - $LOVELACE_AMOUNT - $FEE)

    if [[ $UTXO_LOVELACE_BALANCE_FINAL -lt 0 ]];
    then
        echo "Warning:"
        echo -e "\tTotal Balance available: $TOTAL_BALANCE is smaller than lovelace amount + fee: $LOVELACE_AMOUNT + $FEE = $(expr $LOVELACE_AMOUNT + $FEE) lovelace"
        if ! promptyn "Do you want to send the maximum possible amount ($(expr $TOTAL_BALANCE - $FEE) lovelace)? (y/n)"; then
            echo "Ok bye!"
            exit 1
        else
            LOVELACE_AMOUNT=$(expr $TOTAL_BALANCE - $FEE)
            UTXO_LOVELACE_BALANCE_FINAL=$(expr $TOTAL_BALANCE - $LOVELACE_AMOUNT - $FEE)
        fi
    fi

    echo "FEE: $FEE"
    echo "UTXO_LOVELACE_BALANCE_FINAL: $UTXO_LOVELACE_BALANCE_FINAL"

    # build the transaction
    if [[ $TXOCNT -eq 2 ]]; then
        echo "Creating a standard transaction between 2 addresses"

        if [[ $UTXO_LOVELACE_BALANCE_FINAL -gt 0 ]];
        then
            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $DEST_PAYMENT_ADDR+$LOVELACE_AMOUNT \
            --tx-out $SOURCE_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL \
            --ttl $TTL \
            --fee $FEE \
            --out-file tx.raw
        else
            # only one output here as SOURCE_PAYMENT_ADDR's balance going to 0
            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $DEST_PAYMENT_ADDR+$LOVELACE_AMOUNT \
            --ttl $TTL \
            --fee $FEE \
            --out-file tx.raw
        fi
    elif [[ $TXOCNT -eq 1 && $STAKE_CERT_FILE != "" ]]; then
        echo "Creating a stake address registration transaction"

        cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $DEST_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL \
        --ttl $TTL \
        --fee $FEE \
        --out-file tx.raw \
        --certificate-file $STAKE_CERT_FILE

        STATE_SUB_STEP_ID="sign.trans"
        STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
        STATE_TRANS_WORK_DIR="transactions/$NOW"
        save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR

        # copy certain files back to the air-gapped environment to continue operation there
        STATE_APPLY_SCRIPT=$ROOT_PATH/apply_state.sh
        echo
        echo "Please copy the following files back to your air-gapped environment home directory and run apply_state.sh."
        echo $STATE_FILE
        echo $CUR_DIR/tx.raw
        echo $STATE_APPLY_SCRIPT

        echo '#!/bin/bash
ROOT_PATH="$(realpath "$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")")"
mkdir -p $ROOT_PATH/transactions/'$NOW'
mv tx.raw $ROOT_PATH/transactions/'$NOW'
echo "state applied, please now run init_stake.sh"' > $STATE_APPLY_SCRIPT

#         echo "#!/bin/bash
# mkdir -p \$HOME/transactions/$NOW
# mv tx.raw \$HOME/transactions/$NOW
# echo \"state applied, please now run init_stake.sh\"" > $STATE_APPLY_SCRIPT

    elif [[ $TXOCNT -eq 1 && $POOL_CERT_FILE != "" && $DELEGATION_CERT_FILE != "" ]]; then
        echo "Creating a stake pool registration transaction"

        if [[ $TOTAL_ASSETS == "" ]]; then
            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $DEST_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL \
            --ttl $TTL \
            --fee $FEE \
            --out-file tx.raw \
            --certificate-file $POOL_CERT_FILE \
            --certificate-file $DELEGATION_CERT_FILE
        else
            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $DEST_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL+"$TOTAL_ASSETS" \
            --ttl $TTL \
            --fee $FEE \
            --out-file tx.raw \
            --certificate-file $POOL_CERT_FILE \
            --certificate-file $DELEGATION_CERT_FILE
        fi

        STATE_SUB_STEP_ID="sign.trans"
        STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
        STATE_TRANS_WORK_DIR="transactions/$NOW"
        save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR

        # copy certain files back to the air-gapped environment to continue operation there
        STATE_APPLY_SCRIPT=$ROOT_PATH/apply_state.sh
        echo
        echo "Please copy the following files back to your air-gapped environment home directory and run apply_state.sh."
        echo $STATE_FILE
        echo $CUR_DIR/tx.raw
        echo $STATE_APPLY_SCRIPT

        echo '#!/bin/bash
ROOT_PATH="$(realpath "$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")")"
mkdir -p $ROOT_PATH/transactions/'$NOW'
mv tx.raw $ROOT_PATH/transactions/'$NOW'
echo "state applied, please now run register_pool.sh"' > $STATE_APPLY_SCRIPT

#         echo "#!/bin/bash
# mkdir -p \$HOME/transactions/$NOW
# mv tx.raw \$HOME/transactions/$NOW
# echo \"state applied, please now run register_pool.sh\"" > $STATE_APPLY_SCRIPT

    elif [[ $TXOCNT -eq 1 && $VOTE_METADATA_JSON != "" ]]; then
        echo "Creating a stake pool vote transaction"

  
        if [[ $TOTAL_ASSETS == "" ]]; then
            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $SOURCE_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL \
            --ttl $TTL \
            --fee $FEE \
            --json-metadata-detailed-schema \
            --metadata-json-file $VOTE_METADATA_JSON \
            --required-signer-hash $COLD_VKEY_HASH \
            --out-file tx.raw
        else
            cardano-cli transaction build-raw \
            $TX_IN \
            --tx-out $SOURCE_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL+"$TOTAL_ASSETS" \
            --ttl $TTL \
            --fee $FEE \
            --json-metadata-detailed-schema \
            --metadata-json-file $VOTE_METADATA_JSON \
            --required-signer-hash $COLD_VKEY_HASH \
            --out-file tx.raw
        fi

        STATE_SUB_STEP_ID="sign.trans"
        STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
        STATE_TRANS_WORK_DIR="transactions/$NOW"
        save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR

        # copy certain files back to the air-gapped environment to continue operation there
        STATE_APPLY_SCRIPT=$ROOT_PATH/apply_state.sh
        echo
        echo "Please copy the following files back to your air-gapped environment home directory and run apply_state.sh."
        echo $STATE_FILE
        echo $CUR_DIR/tx.raw
        echo $STATE_APPLY_SCRIPT

        echo '#!/bin/bash
ROOT_PATH="$(realpath "$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")")"
mkdir -p $ROOT_PATH/transactions/'$NOW'
mv tx.raw $ROOT_PATH/transactions/'$NOW'
echo "state applied, please now run spo_poll_vote.sh"' > $STATE_APPLY_SCRIPT

#         echo "#!/bin/bash
# mkdir -p \$HOME/transactions/$NOW
# mv tx.raw \$HOME/transactions/$NOW
# echo \"state applied, please now run spo_poll_vote.sh\"" > $STATE_APPLY_SCRIPT
    fi

fi

if [[ $STATE_SUB_STEP_ID == "sign.trans" && $NODE_TYPE == "airgap" && $IS_AIR_GAPPED == 1 ]]; then
    echo
    echo '---------------- Signing the transaction... ----------------'
    # calculate the number of witness to the transaction
    WITCNT=1
    if [[ $STAKE_CERT_FILE != "" ]]; then WITCNT=2; fi
    if [[ $VOTE_METADATA_JSON != "" ]]; then WITCNT=2; fi
    if [[ $DELEGATION_CERT_FILE != "" ]]; then WITCNT=3; fi

    CUR_DIR=$ROOT_PATH/$STATE_TRANS_WORK_DIR
    cd $CUR_DIR

    # sign the transaction
    if [[ $WITCNT -eq 1 ]]; then
        echo "Signing the transaction with one witness"

        cardano-cli transaction sign \
        --tx-body-file tx.raw \
        --signing-key-file $SKEY_FILE \
        --mainnet \
        --out-file tx.signed
    elif [[ $WITCNT -eq 2 ]]; then
        if [[ $VOTE_METADATA_JSON != "" ]]; then
            echo "Signing the vote transaction with two witnesses"

            cardano-cli transaction sign \
            --tx-body-file tx.raw \
            --signing-key-file $SKEY_FILE \
            --signing-key-file $COLD_KEY_FILE \
            --mainnet \
            --out-file tx.signed
        else
            echo "Signing the transaction with two witnesses"

            cardano-cli transaction sign \
            --tx-body-file tx.raw \
            --signing-key-file $SKEY_FILE \
            --signing-key-file $SKEY_FILE_STAKE \
            --mainnet \
            --out-file tx.signed
        fi

        STATE_SUB_STEP_ID="submit.trans"
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

        ACTION="init_stake.sh"
        if [[ $VOTE_METADATA_JSON != "" ]]; then
            ACTION="spo_poll_vote.sh"
        fi

        # copy certain files to usb key to continue operations on bp node
        cp $STATE_FILE $SPOT_USB_KEY
        cp $CUR_DIR/tx.signed $SPOT_USB_KEY
        STATE_APPLY_SCRIPT=$SPOT_USB_KEY/apply_state.sh

        echo '#!/bin/bash
ROOT_PATH="$(realpath "$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")")"
mkdir -p $ROOT_PATH/'$STATE_TRANS_WORK_DIR'
mv tx.signed $ROOT_PATH/'$STATE_TRANS_WORK_DIR'
echo "state applied, please now run '$ACTION'"' > $STATE_APPLY_SCRIPT

#         echo "#!/bin/bash
# mkdir -p \$HOME/$STATE_TRANS_WORK_DIR
# mv tx.signed \$HOME/$STATE_TRANS_WORK_DIR
# echo \"state applied, please now run $ACTION\"" > $STATE_APPLY_SCRIPT

        echo
        echo "Now copy all files in $SPOT_USB_KEY to your bp node home folder and run apply_state.sh."
        
    elif [[ $WITCNT -eq 3 ]]; then
        echo "Signing the transaction with three witnesses"

        cardano-cli transaction sign \
        --tx-body-file tx.raw \
        --signing-key-file $SKEY_FILE \
        --signing-key-file $SKEY_FILE_STAKE \
        --signing-key-file $COLD_KEY_FILE \
        --mainnet \
        --out-file tx.signed

        STATE_SUB_STEP_ID="submit.trans"
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
        cp $CUR_DIR/tx.signed $SPOT_USB_KEY
        STATE_APPLY_SCRIPT=$SPOT_USB_KEY/apply_state.sh

        echo '#!/bin/bash
ROOT_PATH="$(realpath "$(dirname "$(dirname "$(dirname "$(dirname "$0")")")")")"
mkdir -p $ROOT_PATH/'$STATE_TRANS_WORK_DIR'
mv tx.signed $ROOT_PATH/'$STATE_TRANS_WORK_DIR'
echo "state applied, please now run register_pool.sh"' > $STATE_APPLY_SCRIPT

#         echo "#!/bin/bash
# mkdir -p \$HOME/$STATE_TRANS_WORK_DIR
# mv tx.signed \$HOME/$STATE_TRANS_WORK_DIR
# echo \"state applied, please now run register_pool.sh\"" > $STATE_APPLY_SCRIPT

        echo
        echo "Now copy all files in $SPOT_USB_KEY to your bp node home folder and run apply_state.sh."
    fi
fi

if [[ $STATE_SUB_STEP_ID == "submit.trans" && $IS_AIR_GAPPED == 0 ]]; then
    echo
    echo '----------------Submitting the transaction... ----------------'
    
    CUR_DIR=$ROOT_PATH/$STATE_TRANS_WORK_DIR
    cd $CUR_DIR

    if ! promptyn "Please confirm you want to proceed with sending transaction $CUR_DIR? (y/n)"; then
        echo "Ok bye!"
        exit 1
    fi
    
    # submit the transaction
    res=$(cardano-cli transaction submit --tx-file tx.signed --mainnet 2>cli.err)

    if [[ -s $CUR_DIR/cli.err ]]; then
        echo
        echo "Warning, the transaction was not submitted, cardano-cli error:"
        cat $CUR_DIR/cli.err
    else
        echo $res
        echo "Transaction sent!"

         #Show the TxID
        TX_ID=$(cardano-cli transaction txid --tx-file tx.signed); 
        echo -e "\e[0m TxID is: \e[32m${txID}\e[0m"
        echo $TX_ID > tx.id

        STATE_SUB_STEP_ID="completed.trans"
        STATE_LAST_DATE=`date +"%Y%m%d_%H%M%S"`
        save_state STATE_STEP_ID STATE_SUB_STEP_ID STATE_LAST_DATE STATE_TRANS_WORK_DIR
    fi
    
    echo
    print_state $STATE_STEP_ID $STATE_SUB_STEP_ID $STATE_LAST_DATE $STATE_TRANS_WORK_DIR
fi

echo
echo "transaction working dir: $CUR_DIR"