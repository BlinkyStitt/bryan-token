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
        # Start anvil in background and capture PID
        # chain 31337 is used for development
        anvil \
            --chain-id 31337 \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            "$@" &

        anvil_pid=$!
        rpc_url="http://127.0.0.1:8545"

        # Set up trap to kill anvil on script exit
        cleanup() {
            echo "Cleaning up anvil process..."
            kill $anvil_pid 2>/dev/null || true
            wait $anvil_pid 
        }
        trap cleanup EXIT INT TERM

        # Wait for anvil to be ready
        echo "Waiting for anvil to start..."
        timeout=30
        count=0
        while ! curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "$rpc_url" > /dev/null 2>&1; do
            sleep 1
            count=$((count + 1))
            if [ $count -ge $timeout ]; then
                echo "ERROR: Anvil failed to start within $timeout seconds"
                exit 1
            fi
        done
        echo "Anvil is ready!"

        # This private key is baked into anvil. DO NOT SEND FUNDS HERE!
        private_key="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
        sender="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

        ./script/deploy_fan_token_factory.sh --rpc-url "$rpc_url" --private-key "$private_key"

        # give some USDC
        usdc_address="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
        cast rpc anvil_setStorageAt "$usdc_address" \
            "$(cast index address "$sender" 9)" \
            "$(cast --to-bytes32 200000000)" \
            --rpc-url "$rpc_url"

        ./script/deploy_bryan.sh --rpc-url "$rpc_url" --private-key "$private_key"

        echo "deploys completed successfully. anvil is ready for use at $rpc_url"

        # wait for the anvil process to exit
        # TODO: only wait if this script is being run interactively. if not run interactively, exit now?
        wait $anvil_pid
        ;;
    test)
        exec forge test \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            "$@"
        ;;
    coverage)
        # we skip scripts because they don't build without ir
        forge coverage \
            --fork-block-number "$block_number" \
            --fork-url "$fork_url" \
            --report lcov \
            --skip script \
            "$@"

        # Generate HTML coverage report if lcov.info exists
        if [ -f "lcov.info" ]; then
            genhtml lcov.info --output-dir coverage

            echo "The coverage index file is at $(pwd)/coverage/index.html"
            echo "The coverage can be opened in a browser with \`open $(pwd)/coverage/index.html\` to open them"
        else
            echo "ERROR! No lcov.info exists! Did the tests pass?"
            exit 1
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
