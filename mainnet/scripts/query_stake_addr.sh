#!/bin/bash

if [[ $# -ge 1 && ! $1 == "" ]]; then STAKE_ADDR=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {stake_addr}"; exit 2; fi

cardano-cli query stake-address-info --address $STAKE_ADDR --mainnet
