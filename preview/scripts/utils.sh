#!/bin/bash

derive_node_path_from_socket () {
    if [[ -z "${CARDANO_NODE_SOCKET_PATH:-}" ]]; then
        echo "derive_node_path_from_socket(): CARDANO_NODE_SOCKET_PATH is not set" >&2
        return 1
    fi

    local socket_path
    socket_path="$(realpath "$CARDANO_NODE_SOCKET_PATH")"

    # Expect: <node_path>/socket/node.socket
    local node_path
    node_path="$(dirname "$(dirname "$socket_path")")"

    if [[ ! -d "$node_path" ]]; then
        echo "derive_node_path_from_socket(): derived NODE_PATH does not exist: $node_path" >&2
        return 1
    fi

    echo "$node_path"
}


# prompt yes no
promptyn () {
    while true; do
        read -p "$1 " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# prompt for a value with proposed default value
prompt_input_default() {
 read -p "$1? (default: $2)"": " val
 val="${val:=$2}"
 echo $val
}

# check no internet connection
check_air_gap() {
    if ping -q -c 1 -W 1 google.com >/dev/null; then
        ret=0
    else
        ret=1
    fi
    echo $ret
 }

# script state utils
save_state () {
  typeset -p "$@" >"$STATE_FILE"
}

print_state () {
  echo "state:" "$@"
}

# spot topology utils
get_topo () {
    TOPO_FILE=$1
    MY_IP=$(hostname -I | xargs)
    NODE_TYPE="unknown"
    BP_IP=""
    BP_PORT=""
    RELAY_IPS=()
    RELAY_NAMES=()
    RELAY_IPS_PUB=()
    RELAY_PORTS=()
    ERROR="none"
    # echo "MY_IP: ${MY_IP}"

    # if [[ -z "$MY_IP" ]]; then
    #     echo "air-gap!"
    # else
    #     echo "online"
    # fi

    if [[ -f "$TOPO_FILE" ]]; then
        if [[ -z "$MY_IP" ]]; then
            NODE_TYPE="airgap"
        fi
        
        while IFS= read -r TOPO; do
            # echo $TOPO
            if [[ ! -z $TOPO ]] && [[ "$TOPO" != \#* ]]; then
                TOPO_IP_PORT=$(awk '{ print $1 }' <<< "${TOPO}")
                TOPO_NAME=$(awk '{ print $2 }' <<< "${TOPO}")
                TOPO_IP_PUB=$(awk '{ print $3 }' <<< "${TOPO}")
                # Split IP:PORT (port is optional)
                TOPO_IP="${TOPO_IP_PORT%%:*}"
                TOPO_PORT="${TOPO_IP_PORT##*:}"
                [[ "$TOPO_PORT" == "$TOPO_IP" ]] && TOPO_PORT=""
                if [[ $TOPO_NAME == "bp" ]]; then
                    BP_IP=$TOPO_IP
                    BP_PORT="${TOPO_PORT:-3000}"
                fi

                if [[ $TOPO_IP == $MY_IP ]]; then
                    if [[ "$TOPO_NAME" == *"bp"* ]]; then
                        if [[ "$NODE_TYPE" == "relay" ]]; then
                            NODE_TYPE="hybrid"
                        else
                            NODE_TYPE="bp"
                        fi
                    elif [[ "$TOPO_NAME" == *"relay"* ]]; then
                        if [[ "$NODE_TYPE" == "bp" ]]; then
                            NODE_TYPE="hybrid"
                        else
                            NODE_TYPE="relay"
                        fi
                    fi
                fi
                if [[ "$TOPO_NAME" == *"relay"* ]]; then
                    RELAY_IPS+=($TOPO_IP)
                    RELAY_NAMES+=($TOPO_NAME)
                    RELAY_IPS_PUB+=($TOPO_IP_PUB)
                    RELAY_PORTS+=("${TOPO_PORT:-3001}")
                fi
            fi
        done <$TOPO_FILE

        # echo "NODE_TYPE: $NODE_TYPE"
        # echo "RELAY_IPS: ${RELAY_IPS[@]}"
        # echo "RELAY_NAMES: ${RELAY_NAMES[@]}"
    else 
        ERROR="$TOPO_FILE does not exist. Please create it as per instructions and run this script again."
    fi

    echo "$ERROR $NODE_TYPE $BP_IP $BP_PORT ${RELAY_IPS[@]} ${RELAY_NAMES[@]} ${RELAY_IPS_PUB[@]} ${RELAY_PORTS[@]}"
}

get_network_magic () {
    local node_path
    node_path="$(derive_node_path_from_socket)" || return 1

    local conf="${node_path}/config/bgenesis.json"

    if [[ ! -f "$conf" ]]; then
        echo "get_network_magic(): byron genesis not found at $conf" >&2
        return 1
    fi

    jq -r '.protocolConsts.protocolMagic' "$conf"
}
