#!/bin/bash
cardano-node run \
  --topology ~/node.relay/config/topology.json \
  --database-path ~/node.relay/db/ \
  --socket-path ~/node.relay/socket/node.socket \
  --host-addr 51.104.251.142 \
  --port 3001 \
  --config ~/node.relay/config/config.json