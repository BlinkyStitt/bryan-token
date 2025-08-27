#!/bin/bash
set -eux -o pipefail

forge script ./script/Bryan.s.sol \
    --account flashprofits \
    --rpc-url https://1rpc.io/base \
    --ffi \
    --verify \
    --verifier etherscan \
    --broadcast
