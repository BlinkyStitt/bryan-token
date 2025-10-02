#!/bin/bash
set -eu -o pipefail

cd "$(dirname "$0")/../"

ENV_FILE=${ENV_FILE:-.env}
if [ -e "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

set -x

forge script ./script/DeployBryan.s.sol \
    --broadcast \
    --ffi \
    "$@"

# TODO: we only want this if we aren't deploying to a fork
    # --verify \
    # --verifier etherscan \
# TODO: think of a better way to optionally include. same for deploy_fan_token_factory.sh
    # --account "$ACCOUNT" \