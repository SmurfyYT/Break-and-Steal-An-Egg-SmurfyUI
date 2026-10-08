#!/usr/bin/env bash
# Smoke-tests a build (plain source) in a fake Roblox, as a phone and as a PC,
# then plays the Farm tab in a fake Break & Steal an Egg. Needs `luau`:
#   https://github.com/luau-lang/luau/releases
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
# the farm in a fake Break & Steal an Egg (steal_game.lua + steal_driver.lua)
{
    sed 's/__DEVICE__/"phone"/g' harness.lua
    cat steal_game.lua
    printf '\nfunction __main(...)\n'
    cat "$FILE"
    printf '\nend\n'
    cat steal_driver.lua
} > "$TMP/run_steal.lua"
if luau "$TMP/run_steal.lua" > "$TMP/out_steal.txt" 2>&1 && grep -q "STEAL TESTS OK" "$TMP/out_steal.txt"; then
    echo "  test farm: ok"
else
    echo "  test farm: FAILED"
    grep -a "FAIL\|attempt\|error" "$TMP/out_steal.txt" | head -12 | cut -c1-300 || true
    status=1
fi
[ -n "${VERBOSE:-}" ] && cat "$TMP/out_steal.txt"
exit $status
