#!/bin/bash
# mine a 
set -eu -o pipefail

cache_dir=broadcast/salts/

mkdir -p "$cache_dir"

cache_file=$cache_dir/$1-$2-$3

if [ ! -e "$cache_file" ]; then
    salt=$(cast create2 \
        --deployer "$1" \
        --starts-with "$2" \
        --init-code-hash "$3" \
        --no-random | grep Salt | awk '{print $2}')

    echo "$salt" > "$cache_file"
fi

cat "$cache_file"
