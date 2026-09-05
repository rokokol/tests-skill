#!/usr/bin/env bash
# One construct per line that a bash older than 4 (or a BSD userland) does not have. The
# guard in check.sh must catch every one of them. This file is a fixture and is never
# linted or sourced, which is why it may hold them at all.
[[ -v SOMEVAR ]]
mapfile -t lines <f
readarray -t lines <f
declare -A map
local -A map
echo "${name,,}"
echo "${name^^}"
sort -rV
