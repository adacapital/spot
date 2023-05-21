#!/bin/bash

# global variables
now=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"
TOPO_FILE=~/pool_topology

# importing utility functions
source $NS_PATH/utils.sh

if [[ $# -eq 1 && ! $1 == "" ]]; then VOTE_TX_HASH=$1;
else 
    echo -e "This script requires input parameters:\n\tUsages:"
    echo -e "\t\t$0 {vote_transaction_hash}"
    exit 2
fi

cd ~

URL="https://raw.githubusercontent.com/cardano-foundation/CIP-0094-polls/main/networks/mainnet/${VOTE_TX_HASH}/poll.json"
echo "URL: $URL"
exit 1

wget $URL

cardano-cli governance answer-poll --poll-file poll.json > poll-answer.json

SPOT_DIR=${HOME}/spot/preview
# RES=$($SPOT_DIR/scripts/create_transaction.sh)
$SPOT_DIR/scripts/create_transaction.sh $(cat ~/tmp/paymentwithstake.addr) ~/tmp/payment.skey ~/tmp/cold.skey ~/tmp/cold.vkey ~/tmp/poll-answer.json



# https://github.com/gitmachtl/scripts/blob/master/cardano/testnet/13b_sendSpoPoll.sh


# dummyRequiredHash="12345678901234567890123456789012345678901234567890123456"
# ${cardanocli} transaction build-raw 
#     ${nodeEraParam} 
#     ${txInString} 
#     --tx-out "${sendToAddr}+1000000${assetsOutString}" 
#     --invalid-hereafter ${ttl} 
#     --fee 0 
#     ${metafileParameter} 
#     --required-signer-hash ${dummyRequiredHash} 
#     --out-file ${txBodyFile}

# ${cardanocli} transaction build-raw
#     ${nodeEraParam}
#     ${txInString}
#     --tx-out "${sendToAddr}+1000000${assetsOutString}"
#     --tx-out ${sendToAddr}+1000000
#     --invalid-hereafter ${ttl}
#     --fee 0
#     ${metafileParameter}
#     --required-signer-hash ${dummyRequiredHash} 
#     --out-file ${txBodyFile}

# fee=$(${cardanocli} transaction calculate-min-fee 
#         --tx-body-file ${txBodyFile}
#         --protocol-params-file <(echo ${protocolParametersJSON})
#         --tx-in-count ${txcnt}
#         --tx-out-count ${rxcnt} 
#         ${magicparam}
#         --witness-count 2 --byron-witness-count 0 | awk '{ print $1 }')

# #Generate Dummy-TxBody file for fee calculation
# dummyRequiredHash="12345678901234567890123456789012345678901234567890123456"


# ${cardanocli} transaction build-raw 
#     ${nodeEraParam}
#     ${txInString}
#     --tx-out "${sendToAddr}+${lovelacesToSend}${assetsOutString}"
#     --invalid-hereafter ${ttl}
#     --fee ${fee}
#     ${metafileParameter}
#     --required-signer-hash ${vkeyNodeHash}
#     --out-file ${txBodyFile}

# ${cardanocli} transaction sign
#     --tx-body-file ${txBodyFile}
#         --signing-key-file <(echo "${skeyJSON}")
#         --signing-key-file <(echo "${skeyNodeJSON}") 
#         ${magicparam} --out-file ${txFile}


# if [[ ${rxcnt} == 1 ]]; then  #Sending ALLFUNDS or sending ALL lovelaces and no assets on the address
#                         ${cardanocli} transaction build-raw ${nodeEraParam} ${txInString} --tx-out "${sendToAddr}+1000000${assetsOutString}" --invalid-hereafter ${ttl} --fee 0 ${metafileParameter} --required-signer-hash ${dummyRequiredHash} --out-file ${txBodyFile}
# 			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
#                         else  #Sending chosen amount of lovelaces or ALL lovelaces but return the assets to the address
#                         ${cardanocli} transaction build-raw ${nodeEraParam} ${txInString} --tx-out "${sendToAddr}+1000000${assetsOutString}" --tx-out ${sendToAddr}+1000000 --invalid-hereafter ${ttl} --fee 0 ${metafileParameter} --required-signer-hash ${dummyRequiredHash} --out-file ${txBodyFile}
# 			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
# 	fi
# fee=$(${cardanocli} transaction calculate-min-fee --tx-body-file ${txBodyFile} --protocol-params-file <(echo ${protocolParametersJSON}) --tx-in-count ${txcnt} --tx-out-count ${rxcnt} ${magicparam} --witness-count 2 --byron-witness-count 0 | awk '{ print $1 }')
# checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi

# #read the needed signing keys into ram
# echo
# skeyNodeJSON=$(read_skeyFILE "${nodeName}.node.skey"); if [ $? -ne 0 ]; then echo -e "\e[35m${skeyNodeJSON}\e[0m\n"; exit 1; else echo -e "\e[32mOK\e[0m\n"; fi
# vkeyNodeHash=$(${cardanocli} key verification-key  --signing-key-file <(echo "${skeyNodeJSON}") --verification-key-file /dev/stdout | jq -r .cborHex | tail -c +5 | xxd -r -ps | b2sum -l 224 -b | cut -d' ' -f 1)
# echo -e "\e[0mBuilding the VKEY-Hash (Pool-ID) for the required signer field: \e[32m${vkeyNodeHash}\e[0m"

# echo
# echo -e "\e[0mBuilding the unsigned transaction body: \e[32m ${txBodyFile} \e[90m"
# echo

# #Building unsigned transaction body
# rm ${txBodyFile} 2> /dev/null
# if [[ ${rxcnt} == 1 ]]; then  #Sending ALL funds  (rxcnt=1)
# 			${cardanocli} transaction build-raw ${nodeEraParam} ${txInString} --tx-out "${sendToAddr}+${lovelacesToSend}${assetsOutString}" --invalid-hereafter ${ttl} --fee ${fee} ${metafileParameter} --required-signer-hash ${vkeyNodeHash} --out-file ${txBodyFile}
# 			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
# 			else  #Sending chosen amount (rxcnt=2), return the rest(incl. assets)
# 			${cardanocli} transaction build-raw ${nodeEraParam} ${txInString} --tx-out ${sendToAddr}+${lovelacesToSend} --tx-out "${sendFromAddr}+${lovelacesToReturn}${assetsOutString}" --invalid-hereafter ${ttl} --fee ${fee} ${metafileParameter} --required-signer-hash ${vkeyNodeHash} --out-file ${txBodyFile}
# 			#echo -e "\n\n\n${cardanocli} transaction build-raw ${nodeEraParam} ${txInString} --tx-out ${sendToAddr}+${lovelacesToSend} --tx-out \"${sendFromAddr}+${lovelacesToReturn}${assetsOutString}\" --invalid-hereafter ${ttl} --fee ${fee} --out-file ${txBodyFile}\n\n\n"
# 			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi


# #Sign the unsigned transaction body with the SecureKey

# 	#read the needed signing keys into ram and sign the transaction
# 	skeyJSON=$(read_skeyFILE "${fromAddr}.skey"); if [ $? -ne 0 ]; then echo -e "\e[35m${skeyJSON}\e[0m\n"; exit 1; else echo -e "\e[32mOK\e[0m\n"; fi

# 	echo -e "\e[0mSign the unsigned transaction body with the \e[32m${fromAddr}.skey\e[0m and \e[32m${nodeName}.node.skey\e[0m: \e[32m ${txFile}\e[0m"
# 	echo

#         ${cardanocli} transaction sign --tx-body-file ${txBodyFile} --signing-key-file <(echo "${skeyJSON}") --signing-key-file <(echo "${skeyNodeJSON}") ${magicparam} --out-file ${txFile}
# 	checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi

# 	#forget the signing keys
# 	unset skeyJSON skeyNodeJSON



# #Do a txSize Check to not exceed the max. txSize value
# cborHex=$(jq -r .cborHex < ${txFile})
# txSize=$(( ${#cborHex} / 2 ))
# maxTxSize=$(jq -r .maxTxSize <<< ${protocolParametersJSON})
# if [[ ${txSize} -le ${maxTxSize} ]]; then echo -e "\e[0mTransaction-Size: ${txSize} bytes (max. ${maxTxSize})\n"
#                                      else echo -e "\n\e[35mError - ${txSize} bytes Transaction-Size is too big! The maximum is currently ${maxTxSize} bytes.\e[0m\n"; exit 1; fi

# #Submit the tx
# echo -ne "\e[0mSubmitting the transaction via the node... "
# ${cardanocli} transaction submit --tx-file ${txFile} ${magicparam}
# checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
# echo -e "\e[32mDONE\n"

# #Show the TxID
# txID=$(${cardanocli} transaction txid --tx-file ${txFile}); echo -e "\e[0m TxID is: \e[32m${txID}\e[0m"
# checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi;
# if [[ "${transactionExplorer}" != "" ]]; then echo -e "\e[0mTracking: \e[32m${transactionExplorer}/${txID}\n\e[0m"; fi
