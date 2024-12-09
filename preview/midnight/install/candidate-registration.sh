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

echo "CANDIDATE REGISTRATION STARTING..."
echo

# Download the zip file
# wget https://github.com/input-output-hk/partner-chains/releases/download/v1.1.0/linux_x86_64.zip

wget -O partner-chains-cli https://github.com/input-output-hk/partner-chains/releases/download/v1.3.0/partner-chains-cli-v1.3.0-x86_64-linux

