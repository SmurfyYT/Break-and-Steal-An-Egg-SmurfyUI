#!/usr/bin/env bash
# Smoke-tests a build (plain or obfuscated) in a fake Roblox, as a phone and
# as a PC, then plays auto steal in a fake Steal An Egg. Needs the `luau`
# command line tool:
#   https://github.com/luau-lang/luau/releases (luau-ubuntu.zip / luau-macos.zip)
#   ./build/test/run.sh SmurfysUI.lua
set -euo pipefail
cd "$(dirname "$0")"
FILE="$(cd - >/dev/null && realpath "$1")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
status=0
for device in phone pc; do
    {
        sed "s/__DEVICE__/\"$device\"/g" harness.lua
        printf '\nfunction __main(...)\n'
        cat "$FILE"
        printf '\nend\n'
        sed "s/__DEVICE__/\"$device\"/g" driver.lua
    } > "$TMP/run_$device.lua"
    if luau "$TMP/run_$device.lua" > "$TMP/out_$device.txt" 2>&1 && grep -q "DONE OK" "$TMP/out_$device.txt"; then
        echo "  test $device: ok"
    else
        echo "  test $device: FAILED"
        grep -a -m3 "attempt\|FAILED\|error" "$TMP/out_$device.txt" | cut -c1-300 || true
        status=1
    fi
done
# auto steal in the fake Steal An Egg (steal_game.lua + steal_driver.lua)
for device in phone pc; do
    {
        sed "s/__DEVICE__/\"$device\"/g" harness.lua
        cat steal_game.lua
        printf '\nfunction __main(...)\n'
        cat "$FILE"
        printf '\nend\n'
        cat steal_driver.lua
    } > "$TMP/run_steal_$device.lua"
    if luau "$TMP/run_steal_$device.lua" > "$TMP/out_steal_$device.txt" 2>&1 && grep -q "STEAL TESTS OK" "$TMP/out_steal_$device.txt"; then
        echo "  test steal ($device): ok"
    else
        echo "  test steal ($device): FAILED"
        grep -a "FAIL\|attempt\|error" "$TMP/out_steal_$device.txt" | head -8 | cut -c1-300 || true
        status=1
    fi
done
exit $status
