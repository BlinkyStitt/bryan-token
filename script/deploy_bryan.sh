#!/bin/bash
set -eux -o pipefail

ACCOUNT="${ACCOUNT:-flashprofits}"

# TODO: we need to do something to find the fanTokenFactory address. get it out of ./broadcast/FanTokenFactory.s.sol/???/run-latest.json?

forge script ./script/Bryan.s.sol \
    --account "$ACCOUNT" \
    --ffi \
    --verify \
    --verifier etherscan \
    --broadcast \
    "$@"
