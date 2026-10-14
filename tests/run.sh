#!/usr/bin/env bash
# Offline load-integrity suite for Fishing Buddy (WoW 3.3.5a, Lua 5.1).
#
#   ./run.sh [REPO_DIR]            default REPO_DIR: the directory above tests/
#   LUA=lua5.1 ./run.sh ...        choose the interpreter (must be Lua 5.1)
#   ./run.sh REPO_DIR --verbose    extra arguments are passed to scenarios.lua
#
# Exit status 0 only if the static audit has no [FAIL] AND no scenario fails unexpectedly
# (scenarios named in expected_failures.txt may fail).
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=${1:-$here/..}
[ $# -gt 0 ] && shift
LUA=${LUA:-lua5.1}
rc=0

echo "################ 1/2 static audit ################"
"$LUA" "$here/static_audit.lua" "$repo" --name FishingBuddy || rc=1

echo
echo "################ 2/2 boot scenarios ################"
xf=$(grep -v '^[[:space:]]*#' "$here/expected_failures.txt" | grep -v '^[[:space:]]*$' | tr '\n' ',' | sed 's/,$//')
"$LUA" "$here/scenarios.lua" "$repo" ${xf:+--expect-fail "$xf"} "$@" || rc=1

echo
[ $rc -eq 0 ] && echo "RESULT: ok" || echo "RESULT: FAILED (see [FAIL] lines above)"
exit $rc
