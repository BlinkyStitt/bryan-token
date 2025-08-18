#!/bin/bash
set -eux -o pipefail

forge script Bryan \
    --account "" \
    --fork-url "https://1rpc.io/base" \
    --broadcast
