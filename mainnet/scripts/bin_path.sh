#!/bin/bash

if [[ $# -eq 1 && ! $1 == "" ]]; then BIN_NAME=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {binaryName}"; exit 2; fi

echo "$(jq -r '."install-plan"[] | select(."component-name" == "exe:'$BIN_NAME'") | ."bin-file"' ~/download/cardano-node/dist-newstyle/cache/plan.json | head -n 1)"
