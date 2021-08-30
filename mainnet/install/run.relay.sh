#!/bin/bash
# loading important environment variables by forcing .bashrc to be reloaded
# useful as this script will be run as a systemd service for which no env variable are preloaded
eval "$(cat ~/.bashrc | tail -n +10)"

cardano-node run \
  --topology ~/node.relay/config/topology.json \
  --database-path ~/node.relay/db/ \
  --socket-path ~/node.relay/socket/node.socket \
  --host-addr 0.0.0.0 \
  --port 3001 \
  --config ~/node.relay/config/config.json