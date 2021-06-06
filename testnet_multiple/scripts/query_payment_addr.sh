#!/bin/bash

if [[ $# -ge 1 && ! $1 == "" ]]; then PAYMENT_ADDR=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {payment_addr}"; exit 2; fi

cardano-cli query utxo --address $PAYMENT_ADDR --testnet-magic 1097911063
