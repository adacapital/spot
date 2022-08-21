#!/bin/bash
# To be run on air-gapped offline environment

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
echo $NS_PATH

# importing utility functions
source $NS_PATH/utils.sh
MAGIC=$(get_network_magic)
echo "NETWORK_MAGIC: $MAGIC"

# retrieve pool identifiers
POOL_ID_BECH32=$(cardano-cli stake-pool id --cold-verification-key-file $HOME/pool_keys/cold.vkey)
POOL_ID_HEX=$(cardano-cli stake-pool id --cold-verification-key-file $HOME/pool_keys/cold.vkey --output-format hex)

# retrieve the pool delegation state
REG_JSON=$(cardano-cli query ledger-state --testnet-magic $MAGIC | jq '.stateBefore.esLState.delegationState.pstate."pParams pState".'\"$POOL_ID_HEX\"'')

# retrieve the pool's stake distribution and rank
STAKE_DIST=$(cardano-cli query stake-distribution --testnet-magic $MAGIC | sort -rgk2 | head -n -2 | nl | grep $POOL_ID_BECH32)
STAKE_DIST_RANK=$(echo $STAKE_DIST | awk '{print $1}')
STAKE_DIST_FRACTION_DEC=$(echo $STAKE_DIST | awk '{print $3}' | awk -F"E" 'BEGIN{OFMT="%10.10f"} {print $1 * (10 ^ $2)}')
STAKE_DIST_FRACTION_PCT=$(echo $STAKE_DIST_FRACTION_DEC*100 | bc )

# build the pool info json file
$(cat <<-END > $HOME/node.bp/pool_info.tmp.json
{
    "pool_id_bech32": "${POOL_ID_BECH32}", 
    "pool_id_hex": "${POOL_ID_HEX}", 
    "delegation_state": ${REG_JSON},
    "stake_distribution_rank": ${STAKE_DIST_RANK},
    "stake_distribution_fraction_pct": ${STAKE_DIST_FRACTION_PCT}
}
END
)

# format json file
cat $HOME/node.bp/pool_info.tmp.json | jq . > $HOME/node.bp/pool_info.json
rm -f $HOME/node.bp/pool_info.tmp.json

# display pool info json file
echo "$HOME/node.bp/pool_info.json"
cat $HOME/node.bp/pool_info.json