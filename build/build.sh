#!/usr/bin/env bash
# Builds the obfuscated file that users load with loadstring.
#   ./build/build.sh [version]        (default version: 1.0)
# Output: dist/version_<version>  -> upload this file to the public repo.
# Needs lua5.1 (apt install lua5.1 / brew install lua@5.1) and git.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0}"
PROMETHEUS_DIR="build/.prometheus"
PROMETHEUS_COMMIT="a4efc5f"

if [ ! -d "$PROMETHEUS_DIR" ]; then
    git clone -q https://github.com/prometheus-lua/Prometheus.git "$PROMETHEUS_DIR"
    git -C "$PROMETHEUS_DIR" checkout -q "$PROMETHEUS_COMMIT"
fi

mkdir -p dist
OUT="dist/version_${VERSION}"
(cd "$PROMETHEUS_DIR" && lua5.1 cli.lua --config ../obfuscate.config.lua --nocolors \
    --out "../../$OUT" ../../SmurfysUI.lua)
echo "Built $OUT ($(wc -c < "$OUT") bytes)"

# smoke-test the build; a broken one is deleted so it can't be uploaded
if command -v luau >/dev/null 2>&1; then
    if ! ./build/test/run.sh "$OUT"; then
        rm -f "$OUT"
        echo "Build failed its tests and was deleted. Run ./build/build.sh again." >&2
        exit 1
    fi
else
    echo "Warning: luau not found, so the build was NOT tested (see build/test/run.sh)." >&2
fi
