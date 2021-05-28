#!/bin/bash

BLOCK_INFO_JSON=$(curl -sd '{"network_identifier": { "blockchain": "cardano", "network": "testnet" }, "block_identifier": {}}' -H "Content-Type: application/json" https://explorer.cardano-testnet.iohkdev.io/rosetta/block)

EPOCH_NO=$(echo $BLOCK_INFO_JSON | jq .block.metadata.epochNo)
SLOT_NO=$(echo $BLOCK_INFO_JSON | jq .block.metadata.slotNo)

# build block info json file
$(cat <<-END > $HOME/node.bp/block_info.tmp.json
{
    "epoch_no": "${EPOCH_NO}", 
    "slot_no": "${SLOT_NO}"
}
END
)

# format json file
cat $HOME/node.bp/block_info.tmp.json | jq . > $HOME/node.bp/block_info.json
rm -f $HOME/node.bp/block_info.tmp.json

# display pool info json file
echo "$HOME/node.bp/block_info.json"
cat $HOME/node.bp/block_info.json