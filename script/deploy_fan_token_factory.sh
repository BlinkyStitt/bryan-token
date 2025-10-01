#!/bin/bash
set -eux -o pipefail

if [ -e .env ]; then
    source .env
fi

forge script ./script/DeployFanTokenFactory.s.sol \
    --account "$ACCOUNT" \
    --ffi \
    --verify \
    --verifier etherscan \
    --broadcast \
    "$@"
