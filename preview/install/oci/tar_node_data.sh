#!/bin/bash

# ./spot/preprod/install/oci/tar_node_data.sh -root_path /home/cardano
# scp file
# tar -xzvf /target/node_archive.tar.gz -C /target
#
# use --strip-component=2 to fit the target path, e.g. will remove /home/cardano and from the current directory will extract to /node.bp/key
# tar -xzvf preprod_relay1_node_archive.tar.gz --strip-components=2 

# Initialize variables
root_path=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -root_path) root_path="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Check if both arguments are provided
if [ -z "$root_path" ]; then
    echo "Usage: $0 -root_path ROOT_PATH"
    exit 1
fi

# Create the tar file
tar -czvf "$root_path/node_archive.tar.gz" \
    "$root_path/node.bp/" \
    "$root_path/node.relay/" \
    "$root_path/keys/" \
    "$root_path/pool_keys/" \
    "$root_path/pool_topology"

echo "Tar file created successfully at $root_path/node_archive.tar.gz"
