#!/bin/bash
# originally, i ran `forge script ./script/Bryan.s.sol --account flashprofits --rpc-url https://1rpc.io/base --ffi --broadcast --verify` but that didn't verify the contract.
set -eux -o pipefail

forge script ./script/Bryan.s.sol \
    --account flashprofits \
    --rpc-url https://1rpc.io/base \
    --ffi \
    --verify \
    --verifier etherscan \
    --broadcast
