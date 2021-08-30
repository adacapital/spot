#!/bin/bash

echo -e "\nChecking pool referenced in mainnet topology:"
curl -s https://explorer.cardano.org/relays/topology.json | grep 51.104.251.142

echo -e "\nChecking prometheus metrics for relay:"
curl -s http://127.0.0.1:12798/metrics | sort

echo -e "\nChecking EKG metrics for relay:"
curl -s -H 'Accept: application/json' http://127.0.0.1:12788 | jq .

echo -e "\nChecking prometheus metrics for bp:"
curl -s http://127.0.0.1:12799/metrics | sort

echo -e "\nChecking EKG metrics for bp:"
curl -s -H 'Accept: application/json' http://127.0.0.1:12789 | jq .