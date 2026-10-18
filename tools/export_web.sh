#!/usr/bin/env bash
# Headless web export to export/web/. Requires export templates installed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p export/web
"$GODOT" --headless --path . --export-release Web export/web/index.html
echo "-> export/web/index.html  (serve: cd export/web && python3 -m http.server 8000)"
