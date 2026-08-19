#!/bin/bash
# Package the workflow into dist/Copy-Rendered-Markdown.alfredworkflow
# (a plain zip of info.plist + scripts + optional icon that Alfred imports).
set -euo pipefail
cd "$(dirname "$0")"

OUT="dist/Copy-Rendered-Markdown.alfredworkflow"

command -v zip >/dev/null 2>&1 || { echo "ERROR: zip not found on PATH" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip not found on PATH" >&2; exit 1; }

chmod +x scripts/*.sh
mkdir -p dist
rm -f "$OUT"

FILES=(info.plist scripts)
[[ -f icon.png ]] && FILES+=(icon.png)

zip -r "$OUT" "${FILES[@]}" -x '*.DS_Store' >/dev/null

echo "Built $OUT"
unzip -l "$OUT"
