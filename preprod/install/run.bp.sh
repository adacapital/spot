#!/bin/bash
# loading important environment variables by forcing .bashrc to be reloaded
# useful as this script will be run as a systemd service for which no env variable are preloaded
eval "$(cat ~/.bashrc | tail -n +10)"

cardano-node run \
  --topology ~/node.bp/config/topology.json \
  --database-path ~/node.bp/db/ \
  --socket-path ~/node.bp/socket/node.socket \
  --host-addr 0.0.0.0 \
  --port 3000 \
  --config ~/node.bp/config/config.json \
  --shelley-kes-key ~/pool_keys/kes.skey \
  --shelley-vrf-key ~/pool_keys/vrf.skey \
  --shelley-operational-certificate ~/pool_keys/node.cert
  