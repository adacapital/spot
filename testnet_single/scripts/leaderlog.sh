#!/bin/bash
# Only relevant for block producing node

NOW=`date +"%Y%m%d_%H%M%S"`
NS_PATH="$HOME/stake-pool-tools/node-scripts"
CNCLI_STATUS=$($NS_PATH/cncli_status.sh | jq -r .status)
EPOCH="${1:-next}"
TIMEZONE="${2:-UTC}"
POOL_ID=$(cat $HOME/node.bp/pool_info.json | jq -r .pool_id_hex)
# echo $EPOCH
# echo $TIMEZONE

if [[ $1 == "--help" || $1 == "--h" ]]; then 
    echo "help"; 
    echo -e "Usage: $0 {epoch [prev, current, next]; default:next} {timezone; default:UTC}"
    exit 2
fi

function getLeader() {
    /usr/local/bin/cncli leaderlog \
        --db $HOME/node.bp/cncli/cncli.db \
        --pool-id  $POOL_ID \
        --pool-vrf-skey $HOME/pool_keys/vrf.skey \
        --byron-genesis $HOME/node.bp/config/bgenesis.json \
        --shelley-genesis $HOME/node.bp/config/sgenesis.json \
        --ledger-set $EPOCH \
        --ledger-state $HOME/node.bp/ledger-state.json \
        --tz $TIMEZONE
}

if [[ $CNCLI_STATUS == "ok" ]]; then
    echo "CNCLI database is synced."
    mv $HOME/node.bp/cncli/leaderlog.json $HOME/node.bp/cncli/leaderlog.$NOW.json
    getLeader > $HOME/node.bp/cncli/leaderlog.json
    # remove leaderlogs older than 15 days
    find $HOME/node.bp/cncli/. -name "leaderlog.*.json" -mtime +15 -exec rm -f '{}' \;
else
    echo "CNCLI database not synced!!!"
fi
