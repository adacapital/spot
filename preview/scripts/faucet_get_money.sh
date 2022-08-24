#!/bin/bash

if [[ $# -ge 1 && ! $1 == "" ]]; then PAYMENT_ADDR=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {payment_addr}"; exit 2; fi

# FAUCET_URL="https://faucet.preview.world.dev.cardano.org/basic-faucet"
FAUCET_URL="https://faucet.preview.world.dev.cardano.org"

API_KEY="nohnuXahthoghaeNoht9Aow3ze4quohc"
QUERY="$FAUCET_URL/send-money/$1?api_key=$API_KEY"

echo "QUERY: $QUERY"

OUTPUT=$(curl -X POST -s "$QUERY")

echo "OUTPUT: $OUTPUT"
# echo $OUTPUT | jq -r ".error.tag"

# {"amount": 10}