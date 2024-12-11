#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
BASE_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
SPOT_DIR="$(realpath "$(dirname "$BASE_DIR")")"
UTILS_PATH="$SPOT_DIR/scripts"
CONF_PATH="$SCRIPT_DIR/config"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "BASE_DIR: $BASE_DIR"
echo "SPOT_DIR: $SPOT_DIR"
echo "UTILS_PATH: $UTILS_PATH"
echo "CONF_PATH: $CONF_PATH"
echo

# exit 1

# importing utility functions
source $UTILS_PATH/utils.sh

echo "MIDNIGHT-INIT STARTING..."
echo

sudo apt update
sudo apt install -y ufw

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw allow 3001/tcp # Cardano relay node 
sudo ufw allow 6001/tcp # Additional Cardano relay node

# Allow Ogmios
sudo ufw allow 1337/tcp

# Allow Kupo
sudo ufw allow 1442/tcp

# Allow Postgres-db-sync
sudo ufw allow 5432/tcp

sudo ufw enable

sudo ufw status verbose

echo "Make sure to add eport 1337 & 1442 to your NSG & Egress rules too!"

