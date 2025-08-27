#!/bin/bash
set -eu -o pipefail

cache_dir=broadcast/salts/

mkdir -p "$cache_dir"

cache_file=$cache_dir/$2-$1

if [ ! -e "$cache_file" ]; then
    salt=$(cast create2 \
        --starts-with "$1" \
        --init-code-hash "$2" \
        --no-random | grep Salt | awk '{print $2}')

    echo "$salt" > "$cache_file"
fi

cat "$cache_file"
