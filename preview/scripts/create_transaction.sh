#!/bin/bash
# In a real life scenario (MAINNET), you need to have your keys under cold storage.
# Meaning signing the transaction need to happen in your cold/offline environement.
# We're ok here as we're only playing with TESTNET.

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology
# CLI_PATH=/home/cardano/.local/bin/
CLI_PATH=${HOME}/.local/bin/CIP-0094
echo "CLI_PATH: $CLI_PATH"

# importing utility functions
source $NS_PATH/utils.sh
MAGIC=$(get_network_magic)
echo "NETWORK_MAGIC: $MAGIC"

if [[ $# -eq 5 && ! $1 == "" && ! $2 == "" && ! $3 == "" && ! $4 == "" && ! $5 == "" ]]; then SOURCE_PAYMENT_ADDR=$1; DEST_PAYMENT_ADDR=""; LOVELACE_AMOUNT=0; SKEY_FILE=$2; SKEY_FILE_STAKE=""; STAKE_CERT_FILE=""; COLD_KEY_FILE=$3; COLD_VKEY_FILE=$4; POOL_CERT_FILE=""; DELEGATION_CERT_FILE=""; VOTE_METADATA_JSON=$5;
elif [[ $# -eq 4 && ! $1 == "" && ! $2 == "" && ! $3 == "" && ! $4 == "" ]]; then SOURCE_PAYMENT_ADDR=$1; DEST_PAYMENT_ADDR=$2; LOVELACE_AMOUNT=$3; SKEY_FILE=$4; SKEY_FILE_STAKE=""; STAKE_CERT_FILE=""; COLD_KEY_FILE=""; POOL_CERT_FILE=""; DELEGATION_CERT_FILE=""; VOTE_METADATA_JSON="";
elif [[ $# -eq 6 && ! $1 == "" && ! $2 == "" && ! $3 == "" && ! $4 == "" && ! $5 == "" && ! $6 == "" ]]; then SOURCE_PAYMENT_ADDR=$1; DEST_PAYMENT_ADDR=$2; LOVELACE_AMOUNT=$3; SKEY_FILE=$4; SKEY_FILE_STAKE=$5; STAKE_CERT_FILE=$6; COLD_KEY_FILE=""; POOL_CERT_FILE=""; DELEGATION_CERT_FILE=""; VOTE_METADATA_JSON="";
elif [[ $# -eq 8 && ! $1 == "" && ! $2 == "" && ! $3 == "" && ! $4 == "" && ! $5 == "" && ! $6 == "" && ! $7 == "" && ! $8 == "" ]]; then SOURCE_PAYMENT_ADDR=$1; DEST_PAYMENT_ADDR=$2; LOVELACE_AMOUNT=$3; SKEY_FILE=$4; SKEY_FILE_STAKE=$5; COLD_KEY_FILE=$6; POOL_CERT_FILE=$7; DELEGATION_CERT_FILE=$8; STAKE_CERT_FILE=""; VOTE_METADATA_JSON="";
else 
    echo -e "This script requires input parameters:\n\tUsages:"
    echo -e "\t\t$0 {source_payment_addr} {pay sign key file} {pool cold vkey file} {pool cold skey file} {vote metadata json file}"
    echo -e "\t\t$0 {source_payment_addr} {dest_payment_addr} {lovelace} {sign key file}"
    echo -e "\t\t$0 {source_payment_addr} {dest_payment_addr} {lovelace} {sign key file} {stake sign key file} {stake certificate file}"
    echo -e "\t\t$0 {source_payment_addr} {dest_payment_addr} {lovelace} {sign key file} {stake sign key file} {cold key file} {pool certificate file} {delegation certificate file}"
    exit 2
fi

echo -e "Sending:\t\t$LOVELACE_AMOUNT lovelace"
echo -e "From address:\t\t$SOURCE_PAYMENT_ADDR"
echo -e "To address:\t\t$DEST_PAYMENT_ADDR"
echo -e "Sign key file:\t\t$SKEY_FILE"
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
mkdir -p ~/transactions
cd ~/transactions
mkdir $now
cd $now
CUR_DIR=`pwd`

# get protocol parameters
${CLI_PATH}/cardano-cli query protocol-parameters --testnet-magic $MAGIC --out-file protocol.json

# determine the TTL (Time To Live) for the transaction
# CTIP : the current tip of the blockchain
CTIP=$(${CLI_PATH}/cardano-cli query tip --testnet-magic $MAGIC | jq -r .slot)
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

        ${CLI_PATH}/cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $DEST_PAYMENT_ADDR+0 \
        --ttl 0 \
        --fee 0 \
        --out-file tx.raw.draft
    elif [[ $STAKE_CERT_FILE != "" ]]; then
        echo "Creating a draft stake address registration transaction"

        ${CLI_PATH}/cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $DEST_PAYMENT_ADDR+0 \
        --ttl 0 \
        --fee 0 \
        --out-file tx.raw.draft \
        --certificate-file $STAKE_CERT_FILE
    elif [[ $DELEGATION_CERT_FILE != "" ]]; then
        echo "Creating a draft stake pool registration transaction"

        ${CLI_PATH}/cardano-cli transaction build-raw \
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

        ${CLI_PATH}/cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $SOURCE_PAYMENT_ADDR+0 \
        --json-metadata-detailed-schema \
        --metadata-json-file $VOTE_METADATA_JSON \
        --ttl 0 \
        --fee 0 \
        --required-signer-hash ${dummyRequiredHash} \
        --out-file ~/tmp/tx.raw.draft
    fi
else
    echo "Creating a draft standard transaction with 2 outputs"

    ${CLI_PATH}/cardano-cli transaction build-raw \
    $TX_IN \
    --tx-out $DEST_PAYMENT_ADDR+$LOVELACE_AMOUNT \
    --tx-out $SOURCE_PAYMENT_ADDR+0 \
    --ttl 0 \
    --fee 0 \
    --out-file tx.raw.draft
fi

# calculate the transaction fee and the final balance for SOURCE_PAYMENT_ADDR
FEE=$(${CLI_PATH}/cardano-cli transaction calculate-min-fee \
   --tx-body-file ~/tmp/tx.raw.draft \
   --tx-in-count ${TXCNT} \
   --tx-out-count ${TXOCNT} \
   --witness-count ${WITCNT} \
   --byron-witness-count 0 \
   --testnet-magic $MAGIC \
   --protocol-params-file protocol.json | awk '{print $1}')

echo "TOTAL_BALANCE: ${TOTAL_BALANCE}"
echo "LOVELACE_AMOUNT: ${LOVELACE_AMOUNT}"
echo "FEE: ${FEE}"

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
        ${CLI_PATH}/cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $DEST_PAYMENT_ADDR+$LOVELACE_AMOUNT \
        --tx-out $SOURCE_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL \
        --ttl $TTL \
        --fee $FEE \
        --out-file tx.raw
    else
        # only one output here as SOURCE_PAYMENT_ADDR's balance going to 0
        ${CLI_PATH}/cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $DEST_PAYMENT_ADDR+$LOVELACE_AMOUNT \
        --ttl $TTL \
        --fee $FEE \
        --out-file tx.raw
    fi
elif [[ $TXOCNT -eq 1 && $STAKE_CERT_FILE != "" ]]; then
    echo "Creating a stake address registration transaction"

    ${CLI_PATH}/cardano-cli transaction build-raw \
    $TX_IN \
    --tx-out $DEST_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL \
    --ttl $TTL \
    --fee $FEE \
    --out-file tx.raw \
    --certificate-file $STAKE_CERT_FILE
elif [[ $TXOCNT -eq 1 && $POOL_CERT_FILE != "" && $DELEGATION_CERT_FILE != "" ]]; then
    echo "Creating a stake pool registration transaction"

    if [[ $TOTAL_ASSETS == "" ]]; then
        ${CLI_PATH}/cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $DEST_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL \
        --ttl $TTL \
        --fee $FEE \
        --out-file tx.raw \
        --certificate-file $POOL_CERT_FILE \
        --certificate-file $DELEGATION_CERT_FILE
    else
        ${CLI_PATH}/cardano-cli transaction build-raw \
        $TX_IN \
        --tx-out $DEST_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL+"$TOTAL_ASSETS" \
        --ttl $TTL \
        --fee $FEE \
        --out-file tx.raw \
        --certificate-file $POOL_CERT_FILE \
        --certificate-file $DELEGATION_CERT_FILE
    fi
elif [[ $TXOCNT -eq 1 && $VOTE_METADATA_JSON != "" ]]; then
    echo "Creating a stake pool vote transaction"

    vkeyNodeHash=$(cat $COLD_VKEY_FILE | jq -r .cborHex | tail -c +5 | xxd -r -ps | b2sum -l 224 -b | cut -d' ' -f 1)

    ${CLI_PATH}/cardano-cli transaction build-raw \
    $TX_IN \
    --tx-out $SOURCE_PAYMENT_ADDR+$UTXO_LOVELACE_BALANCE_FINAL \
    --ttl $TTL \
    --fee $FEE \
    --json-metadata-detailed-schema \
    --metadata-json-file $VOTE_METADATA_JSON \
    --required-signer-hash ${vkeyNodeHash} \
    --out-file ~/tmp/tx.raw
fi

# sign the transaction
if [[ $WITCNT -eq 1 ]]; then
    echo "Signing the transaction with one witness"

    ${CLI_PATH}/cardano-cli transaction sign \
    --tx-body-file tx.raw \
    --signing-key-file $SKEY_FILE \
    --testnet-magic $MAGIC \
    --out-file tx.signed
elif [[ $WITCNT -eq 2 ]]; then
    if [[ $VOTE_METADATA_JSON != "" ]]; then
        echo "Signing the vote transaction with two witnesses"
        ${CLI_PATH}/cardano-cli transaction sign \
        --tx-body-file ~/tmp/tx.raw \
        --signing-key-file $SKEY_FILE \
        --signing-key-file $COLD_KEY_FILE \
        --testnet-magic $MAGIC \
        --out-file ~/tmp/tx.signed
    else
        echo "Signing the transaction with two witnesses"
        ${CLI_PATH}/cardano-cli transaction sign \
        --tx-body-file tx.raw \
        --signing-key-file $SKEY_FILE \
        --signing-key-file $SKEY_FILE_STAKE \
        --testnet-magic $MAGIC \
        --out-file tx.signed
    fi
elif [[ $WITCNT -eq 3 ]]; then
    echo "Signing the transaction with three witnesses"

    ${CLI_PATH}/cardano-cli transaction sign \
    --tx-body-file tx.raw \
    --signing-key-file $SKEY_FILE \
    --signing-key-file $SKEY_FILE_STAKE \
    --signing-key-file $COLD_KEY_FILE \
    --testnet-magic $MAGIC \
    --out-file tx.signed
fi

# submit the transaction
${CLI_PATH}/cardano-cli transaction submit \
--tx-file ~/tmp/tx.signed \
--testnet-magic $MAGIC

TXID=$(${CLI_PATH}/cardano-cli transaction txid --tx-file ./tx.signed)

echo "TXID: $TXID"
echo "transaction working dir: $CUR_DIR"