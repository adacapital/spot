#!/bin/bash
# Only relevant for block producing node

cardano-cli query ledger-state --testnet-magic 1097911063 > $HOME/node.bp/ledger-state.json
