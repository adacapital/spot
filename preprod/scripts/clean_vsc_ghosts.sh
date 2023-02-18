#!/bin/bash
# global variables
NOW=`date +"%Y%m%d_%H%M%S"`
TOPO_FILE=~/pool_topology
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SPOT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
NS_PATH="$SPOT_DIR/scripts"

# importing utility functions
source $NS_PATH/utils.sh

echo "VSCode ghost candidate pids:"
ps -eaf | grep vscode |  awk '{print $2}'

if ! promptyn "Kill those pids? (y/n)"; then
    echo "Ok bye!"
    exit 1
fi

ps -eaf | grep vscode |  awk '{print $2}' | while read pid; do
    echo "Killing pid: $pid"
    kill $pid
done

echo "Remaining pids:"
ps -eaf | grep vscode |  awk '{print $2}'

echo "Done"