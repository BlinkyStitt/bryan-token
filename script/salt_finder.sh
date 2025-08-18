#!/bin/bash
set -eu -o pipefail

cast create2 \
    --starts-with "$1" \
    --init-code-hash "$2" \
    --no-random | grep Salt | awk '{print $2}' \
;
