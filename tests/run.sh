#!/usr/bin/env bash
# Runs SmurfySimple.lua in a fake Roblox + fake Break & Steal an Egg.
# Needs the luau CLI (https://github.com/luau-lang/luau/releases):
#   ./tests/run.sh            (VERBOSE=1 for the full log)
set -euo pipefail
cd "$(dirname "$0")"
LUAU="${LUAU:-luau}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
status=0
for device in phone pc; do
    {
        sed "s/__DEVICE__/\"$device\"/g" harness.lua
        cat fake_game.lua
        printf '\nfunction __main(...)\n'
        cat ../SmurfySimple.lua
        printf '\nend\n'
        cat driver.lua
    } > "$TMP/run.lua"
    if "$LUAU" "$TMP/run.lua" > "$TMP/out.txt" 2>&1 && grep -q "ALL TESTS OK" "$TMP/out.txt"; then
        echo "test $device: ok"
    else
        echo "test $device: FAILED"
        grep -a "FAIL\|error\|attempt" "$TMP/out.txt" | head -20 | cut -c1-300 || true
        status=1
    fi
    [ -n "${VERBOSE:-}" ] && cat "$TMP/out.txt"
done
exit $status
