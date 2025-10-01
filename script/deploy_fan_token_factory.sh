#!/bin/bash
set -eux -o pipefail

ENV_FILE=${ENV_FILE:-.env}
if [ -e "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

forge script ./script/DeployFanTokenFactory.s.sol \
    --broadcast \
    --ffi \
    "$@"

# TODO: we only want these if we aren't 
    # --verify \
    # --verifier etherscan \
# TODO: specify an account here? that gets in the way of testing
    # --account "$ACCOUNT" \
