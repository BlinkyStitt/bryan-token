#!/bin/bash
set -eux -o pipefail

ACCOUNT="${ACCOUNT:-flashprofits}"

forge script ./script/FanTokenFactory.s.sol \
    --account "$ACCOUNT" \
    --ffi \
    --verify \
    --verifier etherscan \
    --broadcast \
    "$@"
