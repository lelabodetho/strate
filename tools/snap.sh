#!/usr/bin/env bash
# Run the harness scene, capture a screenshot and the sim state, then quit.
# Usage: tools/snap.sh [name] [frames] [seed]
# Output: tools/out/<name>.png and tools/out/<name>.json
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="${1:-snap}"; FRAMES="${2:-30}"; SEED="${3:-1}"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p tools/out
"$GODOT" --path . --scene res://scenes/test/harness.tscn --resolution 1280x720 \
  -- --screenshot="$PWD/tools/out/$NAME.png" --state="$PWD/tools/out/$NAME.json" --frames="$FRAMES" --seed="$SEED" \
  2>&1 | grep -E '^\[harness\]|ERROR|SCRIPT ERROR' || true
echo "-> tools/out/$NAME.png  tools/out/$NAME.json"
