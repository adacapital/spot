#!/bin/bash

# Initialize variables
node_type=""
root_path=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -node_type) node_type="$2"; shift ;;
        -root_path) root_path="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Check if both arguments are provided
if [ -z "$node_type" ] || [ -z "$root_path" ]; then
    echo "Usage: $0 -node_type NODE_TYPE -root_path ROOT_PATH"
    exit 1
fi

# Create the tar file
tar -czvf "$root_path/node_archive.tar.gz" \
    "$root_path/$node_type/" \
    "$root_path/keys/" \
    "$root_path/pool_keys/" \
    "$root_path/pool_topology"

echo "Tar file created successfully at $root_path/node_archive.tar.gz"
