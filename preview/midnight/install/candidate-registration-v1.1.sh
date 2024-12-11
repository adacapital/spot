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

echo
echo "CANDIDATE REGISTRATION STARTING..."
INSTALL_PATH=$BASE_DIR
INSTALL_PATH=$(prompt_input_default INSTALL_PATH $INSTALL_PATH)

echo
echo "Details of your cardano-db-sync build:"
echo "INSTALL_PATH: $INSTALL_PATH"
if ! promptyn "Please confirm you want to proceed? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi


cd $INSTALL_PATH
mkdir -p partner-chains-v1
cd partner-chains-v1

wget https://github.com/input-output-hk/partner-chains/releases/download/v1.1.0/linux_x86_64.zip

unzip linux_x86_64.zip

find . -name "*.zip" -exec unzip {} \; -exec rm {} \;

# Define the JSON content
json_content=$(cat <<EOF
{
    "cardano": {
        "network": 2,
        "security_parameter": 432,
        "active_slots_coeff": 0.05,
        "first_epoch_number": 0,
        "first_slot_number": 0,
        "epoch_duration_millis": 86400000,
        "first_epoch_timestamp_millis": 1666656000000
    },
    "chain_parameters": {
        "chain_id": 23,
        "genesis_committee_utxo": "f44d20261bd3e079cc76b4d9b32b3330fea793b465c490766df71be90e577d8a#0",
        "threshold_numerator": 2,
        "threshold_denominator": 3,
        "governance_authority": "93f21ad1bba9ffc51f5c323e28a716c7f2a42c5b51517080b90028a6"
    },
    "cardano_addresses": {
        "committee_candidates_address": "addr_test1wp9pehc6t5xem0ccsf7dhktw4hu749dfm83fxx6p8f4jzpqyh330x",
        "d_parameter_policy_id": "f7e7b40ef803905a8567323f9d94fac536fe1cd3d8efbde5d249c5f7",
        "permissioned_candidates_policy_id": "3e0a39f32961debeb7c5db0e5deb98833d70835fc7ec40a3185c4ae5"
    }
}
EOF
)

# Create the file and write the JSON content to it
echo "$json_content" > partner-chains-cli-chain-config.json

# Check if the file was created successfully
if [ -f partner-chains-cli-chain-config.json ]; then
    echo "File 'partner-chains-cli-chain-config.json' has been created successfully."
else
    echo "Failed to create the file."
fi

# Generate Partner-chain keys
./partner-chains-cli generate-keys


