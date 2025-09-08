#!/bin/bash
# run tests on a forked network on a recent block
set -eux -o pipefail

REORG_SAFETY=${REORG_SAFETY:-5}

# TODO: whats the actual max lag?
MAX_LAG_BLOCKS=${MAX_LAG_BLOCKS:-4096}

fork_url=https://1rpc.io/${ONERPC_API_KEY}/base

block_number=$(cast block-number --rpc-url "$fork_url")

if [ "$block_number" -gt "$REORG_SAFETY" ]; then
    block_number=$(( block_number - REORG_SAFETY ))
else
    block_number=0
fi

block_cache_dir="./cache/block-number/"

mkdir -p "$block_cache_dir"

block_cache="./cache/block-number/test"

if [ -e "$block_cache" ]; then
    last_used=$(cat "$block_cache")

    lag=$(( block_number + REORG_SAFETY - last_used ))
    if [ "$lag" -gt "$MAX_LAG_BLOCKS" ]; then
        echo "$block_number" > "$block_cache"
    else
        block_number=$last_used
    fi
else
    echo "$block_number" > "$block_cache"
fi

# TODO: easily run `snapshot` or `coverage` instead of only `test`

exec forge test \
    --fork-block-number "$block_number" \
    --fork-url "$fork_url" \
    "$@"
