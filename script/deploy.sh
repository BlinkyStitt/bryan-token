#!/bin/bash
set -eux -o pipefail

forge script Bryan \
    --account "flashprofits" \
    --fork-url "https://1rpc.io/base" \
    --broadcast \
    --ffi \
    --slow \
;
