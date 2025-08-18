#!/bin/bash
set -eux -o pipefail

cast create2 \
    --starts-with "$1" \
    --init-code "$2" \
    --no-random | grep Salt | awk '{print $2}'
;
