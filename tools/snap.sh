#!/usr/bin/env bash
# Run the harness scene, capture a screenshot and the sim state, then quit.
# Usage: tools/snap.sh [name] [frames] [seed] [extra --flags passed to GameState, e.g. --hold=attack --dash=100]
# --mode=pixel|dither|mix (or --render) runs scenes/test/render_test.tscn instead of the harness.
# Output: tools/out/<name>.png and tools/out/<name>.json
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="${1:-snap}"; FRAMES="${2:-30}"; SEED="${3:-1}"; shift $(( $# < 3 ? $# : 3 ))
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  for c in /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Applications/Godot.app/Contents/MacOS/Godot" "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
    [ -x "$c" ] && GODOT="$c" && break
  done
fi
[ -x "${GODOT:-}" ] || { echo "Godot not found; set GODOT=/path/to/Godot" >&2; exit 1; }
mkdir -p tools/out
SCENE=res://scenes/test/harness.tscn
for a in "$@"; do case "$a" in --mode=*|--render) SCENE=res://scenes/test/render_test.tscn;; esac; done
"$GODOT" --path . --scene "$SCENE" --resolution 1280x720 \
  -- --screenshot="$PWD/tools/out/$NAME.png" --state="$PWD/tools/out/$NAME.json" --frames="$FRAMES" --seed="$SEED" "$@" \
  2>&1 | grep -E '^\[harness\]|ERROR|SCRIPT ERROR' || true
echo "-> tools/out/$NAME.png  tools/out/$NAME.json"
