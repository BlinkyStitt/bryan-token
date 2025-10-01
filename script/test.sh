#!/bin/bash
# run tests on a forked network on a recent block
set -eu -o pipefail

cd "$(dirname "$0")/../"

ENV_FILE=${ENV_FILE:-.env}
if [ -e "$ENV_FILE" ]; then
    source "$ENV_FILE"
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
        anvil \
            --auto-impersonate \
            --chain-id 18543 \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            "$@" &

        # TODO: why isn't this working?
        # anvil_pid=$!
        # trap "kill $anvil_pid" EXIT

        # TODO: trap to kill anvil

        # TODO: sleep until 8545 is open. it starts faster than 3 seconds
        sleep 3

        # This private key is baked into anvil. DO NOT SEND FUNDS HERE!
        ./script/deploy_fan_token_factory.sh --rpc-url "http://127.0.0.1:8545" --private-key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
        ./script/deploy_bryan.sh --rpc-url "http://127.0.0.1:8545" --private-key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

        echo "deploys complete. anvil is ready for use"

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
