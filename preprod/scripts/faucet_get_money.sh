#!/bin/bash

# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
LOCKFILE="/tmp/faucet_get_money_lock"
OUTFILE="/tmp/faucet_get_money.out"

if [ -f $LOCKFILE ]
then
    echo "Lockfile exists, refusing to run"
    exit 1
fi

rm -f $OUTFILE
echo $NOW >> $OUTFILE

# See if the env flag is set
if [ "$FORKED_TO_BG" = "" ]
then
    # Fork self to background
    FORKED_TO_BG=1 nohup $0 $@ 2>&1 >/dev/null
    # echo "$$ Forked"
    exit 0
fi

# Do stuff
touch $LOCKFILE
echo "$$ Running normally" >> $OUTFILE

if [[ $# -ge 1 && ! $1 == "" ]]; then PAYMENT_ADDR=$1; else echo -e "This script requires input parameters:\n\tUsage: $0 {payment_addr}" >> $OUTFILE; rm $LOCKFILE; exit 2; fi

FAUCET_URL="https://faucet.preprod.world.dev.cardano.org"
API_KEY="ooseiteiquo7Wie9oochooyiequi4ooc"
QUERY="$FAUCET_URL/send-money/$1?api_key=$API_KEY"

echo "QUERY: $QUERY" >> $OUTFILE

OUTPUT=$(curl -X POST -s "$QUERY")

echo "OUTPUT: $OUTPUT" >> $OUTFILE
# echo $OUTPUT | jq -r ".amount"
ERROR=$(echo $OUTPUT | jq -r ".error.tag")

if [ $ERROR == "FaucetWebErrorRateLimitExeeeded" ];then
    WAIT_SECONDS=$(echo $OUTPUT | jq -r ".error.contents" | jq '.[0]')
    SLEEP_SECONDS=$(echo $WAIT_SECONDS + 1 | bc)
    
    echo "Asked to wait for $WAIT_SECONDS seconds, sleeping for $SLEEP_SECONDS seconds" >> $OUTFILE

    sleep $SLEEP_SECONDS

    echo "QUERY: $QUERY" >> $OUTFILE

    OUTPUT=$(curl -X POST -s "$QUERY")

    echo "OUTPUT: $OUTPUT" >> $OUTFILE
fi

rm $LOCKFILE
# {"amount":{"lovelace":10000200000},"txid":"958109e68de0f1a8a6f9f1953154b79841820012b629603995c92aebcc6221e7","txin":"16304732e3b1d51f8fb4c95c1a24781dd85824b1b506a62488a85b1da4c801af#58"}
# {"error":{"contents":[79755.8929501,"addr_test1qrprkvu5c4un868k57796qdxurrmdus2z4da7265sfe65aykpjwsvsp2z84j6fwynntrh0wzshh2fxcww289ljrxhrwqgfhuj2"],"tag":"FaucetWebErrorRateLimitExeeeded"}}