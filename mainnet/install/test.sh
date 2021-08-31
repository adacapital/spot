#!/bin/bash
TOPO_FILE=~/pool_topology
MY_IP=$(hostname -I | xargs)
NODE_TYPE=""
RELAYS=()
echo "MY_IP: ${MY_IP}"

if [[ -f "$TOPO_FILE" ]]; then
    echo "Working on topo file..."
    while IFS= read -r TOPO; do
        echo $TOPO
        if [[ ! -z $TOPO ]]; then
            TOPO_IP=$(awk '{ print $1 }' <<< "${TOPO}")
            TOPO_NAME=$(awk '{ print $2 }' <<< "${TOPO}")
            #echo "TOPO_IP: ${TOPO_IP}"
            #echo "TOPO_NAME: ${TOPO_NAME}"
            if [[ $TOPO_IP == $MY_IP ]]; then
                if [[ "$TOPO_NAME" == *"bp"* ]]; then
                    NODE_TYPE="bp"
                elif [[ "$TOPO_NAME" == *"relay"* ]]; then
                    NODE_TYPE="relay"
                fi
            else
                if [[ "$TOPO_NAME" == *"relay"* ]]; then
                    RELAYS+=($TOPO_IP)
                fi
            fi
        fi
    done <$TOPO_FILE

    echo "NODE_TYPE: $NODE_TYPE"
    echo "RELAYS: ${RELAYS[@]}"
    echo "RELAYS length: ${#RELAYS[@]}"
else 
    echo "$TOPO_FILE does not exist. Please create it as per instructions and run this script again."
    exit 1
fi

exit 1

source $HOME/stake-pool-tools/node-scripts/utils.sh

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
PARENT_SCRIPT_DIR="$(realpath "$(dirname "$SCRIPT_DIR")")"
echo $SCRIPT_DIR
echo $PARENT_SCRIPT_DIR
exit 1

if promptyn "do you want to continue? (y/n)"; then
    echo "yes"
else
    echo "no"
fi

exit 1

now=`date +"%Y%m%d"`
echo 'curr time:'$now

str="c5ce0195143a25e4fc959412d377d62ac2012b81d9724ba392e7865b603ed7cd     0        1000000000 lovelace"
str2=$(echo $str | awk '{print $1}')
echo "str2: ${str2}_"
exit 1

CNODE_HOME="$HOME/node.relay"                        # Override default CNODE_HOME path (defaults to /opt/cardano/cnode)
CONFIG="${CNODE_HOME}/config/config.json"  

echo ${CONFIG}
jq -r . ${CONFIG} | head -n 1

if ! jq -r . ${CONFIG} >/dev/null 2>&1; then
    echo "Could not parse ${CONFIG} file in JSON format, please double-check the syntax of your config, or simply download it from guild-operators repository!"
else
    echo "OK"
fi

exit 1

if [ $? -gt 0 ]; then
    echo "not found"
else
    echo "found"
fi

exit 1

echo "\$PATH Before: $PATH"

echo $PATH | grep -q "/usr/local/bin"

if [[ ! ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    echo "/usr/local/lib not found in \$PATH"
else
   echo "/usr/local/lib found in \$PATH"
fi

exit 1

if [[ ! ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    echo "$HOME/.local/bin not found in $PATH"
    echo "Tweaking your .bashrc"
    echo $"if [[ ! ":'$PATH':" == *":'$HOME'/.local/bin:"* ]]; then
    export PATH=\$HOME/.local/bin:\$PATH
fi" >> ~/.bashrc
    eval "$(cat ~/.bashrc | tail -n +10)"
    echo "After: $PATH"
else
    echo "$HOME/.local/bin found in $PATH, nothing to change here."
fi

exit 1

echo $"if [[ ! ":'$PATH':" == *":'$HOME'/.local/bin:"* ]]; then
    export PATH=\$HOME/.local/bin:\$PATH
fi" >> ~/.bashrc 

exit 1

echo $PATH | grep -q "$HOME/.local/bin"

if [ $? -gt 0 ]; then
    echo "$HOME/.local/bin not found in $PATH"
    echo "Tweaking your .bashrc"
    echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc 
    eval "$(cat ~/.bashrc | tail -n +10)"
else
    echo "$HOME/.local/bin found in $PATH, nothing to change here."
fi

echo "After: $PATH"
