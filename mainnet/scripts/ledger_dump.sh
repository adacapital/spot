#!/bin/bash
# Only relevant for block producing node

cardano-cli query ledger-state --mainnet > $HOME/node.bp/ledger-state.json
