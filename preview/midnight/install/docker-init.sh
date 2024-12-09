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

echo "DOCKER-INIT STARTING..."
echo

echo "Update the Package List"
echo
sudo apt-get update

echo "Install Prerequisite Packages"
echo
sudo apt-get install \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

echo "Add Docker Official GPG Key"
echo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "Set Up the Stable Repository"
echo
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Update the Package List"
echo
sudo apt-get update

echo "Install Docker Engine"
echo
sudo apt-get install docker-ce docker-ce-cli containerd.io

echo "Verify the Installation"
echo
sudo docker run hello-world
