#!/bin/bash
# Converts whatever markdown is currently on the clipboard to RTF, in place.
# Source-agnostic: doesn't care whether the markdown came from Claude Code,
# an editor, a browser, or anywhere else.
set -euo pipefail

if ! command -v pandoc >/dev/null 2>&1; then
  echo "ERROR: pandoc not found on PATH — install it with 'brew install pandoc'" >&2
  exit 2
fi

if ! command -v pbcopy >/dev/null 2>&1 || ! command -v pbpaste >/dev/null 2>&1; then
  echo "ERROR: pbcopy/pbpaste not found on PATH — macOS only" >&2
  exit 3
fi

markdown=$(pbpaste)

if [ -z "$markdown" ]; then
  echo "ERROR: clipboard is empty" >&2
  exit 1
fi

if ! rtf=$(printf '%s' "$markdown" | pandoc -f markdown -t rtf -s 2>&1); then
  echo "ERROR: pandoc conversion failed: $rtf" >&2
  exit 4
fi

if ! printf '%s' "$rtf" | pbcopy -Prefer rtf; then
  echo "ERROR: pbcopy failed" >&2
  exit 5
fi

bytes=$(printf '%s' "$rtf" | wc -c | tr -d ' ')
echo "copied as rich text — ${bytes} bytes RTF"
