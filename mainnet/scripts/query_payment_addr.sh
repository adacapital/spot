#!/bin/bash

if [[ $# -eq 1 && ! $1 == "" ]]; then PAYMENT_ADDR=$1; ADV_FLAG="N"; 
elif [[ $# -eq 2 && ! $1 == "" && ! $2 == "" ]]; then 
    PAYMENT_ADDR=$1; 
    ADV_FLAG="N";
    if [[ $2 == "-a" ]]; then
        ADV_FLAG="Y";
    fi
else echo -e "This script requires input parameters:\n\tUsage: $0 {payment_addr} -a {advanced flag:optional}"; exit 2; fi

if [[ $ADV_FLAG == "N" ]]; then
    cardano-cli query utxo --address $PAYMENT_ADDR --mainnet
else
    rm -f /tmp/query_payment_addr.out /tmp/utxos.out
    cardano-cli query utxo --address $PAYMENT_ADDR --mainnet > /tmp/query_payment_addr.out
    cat /tmp/query_payment_addr.out

    # get utx0 details of SOURCE_PAYMENT_ADDR
    UTXO_RAW=$($NS_PATH/query_payment_addr.sh $SOURCE_PAYMENT_ADDR > query_payment_addr.out) 

    tail -n +3 /tmp/query_payment_addr.out | sort -k3 -nr > /tmp/utxos.out

    TX_IN=""
    TOTAL_BALANCE=0
    while read -r UTXO; do
        UTXO_HASH=$(awk '{ print $1 }' <<< "${UTXO}")
        UTXO_TXIX=$(awk '{ print $2 }' <<< "${UTXO}")
        UTXO_BALANCE=$(awk '{ print $3 }' <<< "${UTXO}")
        TOTAL_BALANCE=$((${TOTAL_BALANCE}+${UTXO_BALANCE}))
        # echo "TxIn: ${UTXO_HASH}#${UTXO_TXIX}"
        # echo "Lovelace: ${UTXO_BALANCE}"
    done < /tmp/utxos.out
    TXCNT=$(cat /tmp/utxos.out | wc -l)
    TOTAL_BALANCE_FORMATED=`echo $TOTAL_BALANCE | sed -r ':a;s/([0-9])([0-9]{3}([^0-9]|$))/\1,\2/;ta'`
    echo
    echo "Total lovelace balance: $TOTAL_BALANCE_FORMATED"
    echo "UTXO count: $TXCNT"
fi
