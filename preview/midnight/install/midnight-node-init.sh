#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
PARENT_DIR2="$(realpath "$(dirname "$PARENT_DIR")")"
PARENT_DIR3="$(realpath "$(dirname "$PARENT_DIR2")")"
BASE_DIR="$(realpath "$(dirname "$PARENT_DIR3")")"
SPOT_DIR=$PARENT_DIR2
UTILS_PATH="$SPOT_DIR/scripts"
CONF_PATH="$SCRIPT_DIR/config"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "BASE_DIR: $BASE_DIR"
echo "PARENT_DIR: $PARENT_DIR"
echo "PARENT_DIR2: $PARENT_DIR2"
echo "PARENT_DIR3: $PARENT_DIR3"
echo "SPOT_DIR: $SPOT_DIR"
echo "UTILS_PATH: $UTILS_PATH"
echo "CONF_PATH: $CONF_PATH"
echo

# exit 1 

# importing utility functions
source $UTILS_PATH/utils.sh

echo "MIDNIGHT-NODE-INIT STARTING..."
echo

cd $BASE_DIR

git clone https://github.com/midnight-ntwrk/midnight-node-docker.git
cd midnight-node-docker

echo
echo "Please update .env accordingly."
echo
echo "To start the node: sudo docker compose up -d"


## Notes:
# 1. Copy content of secret_ed25519 created in step 3 into NODE_KEY in .env
# 2. Copy /partner-chains-v1/data to /midnight-node-docker


## Script to validate the midnight keys generated in step 3
# for key in $( ls data/chains/partner_chains_template/keystore/ )
# do 
#     set $( echo "$key" | sed 's#^\(........\)#\1 #' )
#     type=$( echo "$1" | xxd -r -p); 
#     dem curl -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"author_hasKey","params":[ "'$2'", "'$type'"]}' http://localhost:9944 | jq .result
# done

# # Where dem is
# alias de='docker exec -it'
# alias dem='de midnight-node-testnet'