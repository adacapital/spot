#!/bin/bash
cardano-node run \
  --topology ~/node.bp/config/topology.json \
  --database-path ~/node.bp/db/ \
  --socket-path ~/node.bp/socket/node.socket \
  --host-addr 51.104.251.142 \
  --port 3000 \
  --config ~/node.bp/config/config.json \
  --shelley-kes-key ~/pool_keys/kes.skey \
  --shelley-vrf-key ~/pool_keys/vrf.skey \
  --shelley-operational-certificate ~/pool_keys/node.cert