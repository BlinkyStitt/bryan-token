#!/bin/bash
# run tests on a forked network on a recent block
set -eux -o pipefail

if [ -e .env ]; then
    source .env
fi

REORG_SAFETY=${REORG_SAFETY:-5}

# TODO: whats the actual max lag?
# TODO: we don't do all 4096 because we need a slow test run to have long enough
MAX_LAG_BLOCKS=${MAX_LAG_BLOCKS:-4000}

fork_url=${BASE_RPC_URL}

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

# Support different modes: test, coverage, snapshot
mode="coverage"  # default to coverage
if [ $# -gt 0 ]; then
    case "$1" in
        test|coverage|snapshot)
            mode="$1"
            shift  # remove mode from arguments
            ;;
    esac
fi

case "$mode" in
    test)
        exec forge test \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            "$@"
        ;;
    coverage)
        exec forge coverage \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            --report lcov \
            "$@"
        ;;
    snapshot)
        exec forge snapshot \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            "$@"
        ;;
esac
