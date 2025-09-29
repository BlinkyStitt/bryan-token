#!/bin/bash
# run tests on a forked network on a recent block
set -eu -o pipefail

cd "$(dirname "$0")/../"

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
mode="test"
if [ $# -gt 0 ]; then
    case "$1" in
        anvil|test|coverage|snapshot)
            mode="$1"
            shift  # remove mode from arguments
            ;;
    esac
fi

case "$mode" in
    anvil)
        anvil --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            --optimism \
            "$@" &

        # TODO: sleep until 8545 is open. it starts faster than 3 seconds
        sleep 3

        # TODO:
        ./script/deploy.sh --rpc-url "http://127.0.0.1:8545"

        # wait for the anvil process to exit
        wait
        ;;
    test)
        exec forge test \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            "$@"
        ;;
    coverage)
        forge coverage \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            --report lcov \
            "$@"

        # Generate HTML coverage report if lcov.info exists
        if [ -f "lcov.info" ]; then
            genhtml lcov.info --output-dir coverage

            echo "The coverage index file is at $(pwd)/coverage/index.html"
            echo "The coverage can be opened in a browser with \`open $(pwd)/coverage/index.html\` to open them"
        else
            echo "ERROR! No lcov.info exists! Did the tests pass?"
        fi
        ;;
    snapshot)
        forge snapshot \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            "$@"
        
        # TODO: is there a way to make it not group lines so that its easy to see the remove and adds together?
        git diff
        ;;
esac
