#!/bin/bash

if [[ $# -ge 1 && ! $1 == "" ]]; then bin_name=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {key_name} {out_dir:optional}"; exit 2; fi

# if out_dir exists, we cd into it to create keys there, otherwise keys are created in current directory
if [ ! -z "$2" ]; then
    cd $2
fi

# generate payment key pair
cardano-cli address key-gen \
--verification-key-file $1.vkey \
--signing-key-file $1.skey

chmod 400 $1.vkey $1.skey

# generate payment address
cardano-cli address build \
--payment-verification-key-file $1.vkey \
--out-file $1.addr \
--mainnet

chmod 400 $1.addr