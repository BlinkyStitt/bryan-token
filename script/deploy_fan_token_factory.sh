#!/bin/bash
set -eu -o pipefail

cd "$(dirname "$0")/../"

ENV_FILE=${ENV_FILE:-.env}
if [ -e "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

set -x

forge script ./script/DeployFanTokenFactory.s.sol \
    --broadcast \
    --ffi \
    "$@"
