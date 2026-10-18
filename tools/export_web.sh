#!/usr/bin/env bash
# Headless web export to export/web/. Requires export templates installed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  for c in /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Applications/Godot.app/Contents/MacOS/Godot" "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
    [ -x "$c" ] && GODOT="$c" && break
  done
fi
[ -x "${GODOT:-}" ] || { echo "Godot not found; set GODOT=/path/to/Godot" >&2; exit 1; }
mkdir -p export/web
"$GODOT" --headless --path . --export-release Web export/web/index.html
echo "-> export/web/index.html  (serve: cd export/web && python3 -m http.server 8000)"
