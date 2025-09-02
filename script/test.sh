#!/bin/bash
set -eux -o pipefail

# TODO: do some queries to pick a good fork block number. we want to use caches for as long as possible, but public nodes don't always offer archive blocks

exec forge test \
    --fork-block-number 35003452 \
    --fork-url https://1rpc.io/base \
    "$@"
