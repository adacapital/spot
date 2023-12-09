#!/bin/bash

# ./spot/preprod/install/oci/tar_node_data.sh -node_type node.bp -root_path /home/cardano
# scp file
# tar -xzvf /target/node_archive.tar.gz -C /target
#
# use --strip-component=2 to fit the target path, e.g. will remove /home/cardano and from the current directory will extract to /node.bp/key
# tar -xzvf preprod_relay1_node_archive.tar.gz --strip-components=2 
#
# or for bp node setup from a node.relay tar to extract just /db
# tar -xzvf mainnet_relay1_node_db_archive.tar.gz --strip-components=3 -C /home/cardano/data/node.bp home/cardano/node.relay/db

# Initialize variables
node_type=""
root_path=""
delta=false

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -node_type) node_type="$2"; shift ;;
        -root_path) root_path="$2"; shift ;;
        -delta) delta=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Check if both arguments are provided
if [ -z "$node_type" ] || [ -z "$root_path" ]; then
    echo "Usage: $0 -node_type NODE_TYPE -root_path ROOT_PATH [-delta]"
    exit 1
fi

if [ "$delta" = true ]; then
    # Create the tar file in delta mode
    tar -czvf "$root_path/node_archive_delta.tar.gz" \
        "$root_path/$node_type/config/" \
        "$root_path/$node_type/socket/" \
        "$root_path/$node_type/"*.*
    echo "Delta tar file created successfully at $root_path/node_archive_delta.tar.gz"
else
    # Create the full tar file
    tar -czvf "$root_path/node_archive.tar.gz" \
        "$root_path/$node_type/" \
        "$root_path/keys/" \
        "$root_path/pool_keys/" \
        "$root_path/pool_topology"
    echo "Full tar file created successfully at $root_path/node_archive.tar.gz"
fi

