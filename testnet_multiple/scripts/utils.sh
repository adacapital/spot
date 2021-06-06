#!/bin/bash

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