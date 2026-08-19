#!/bin/bash
# Converts whatever markdown is currently on the clipboard to rendered rich
# text, in place. Source-agnostic: doesn't care whether the markdown came
# from Claude Code, an editor, a browser, or anywhere else.
#
# Writes three pasteboard flavors at once (public.html, public.rtf,
# public.utf8-plain-text) via write-clipboard.jxa.js. RTF alone is not
# enough: Chromium/Electron apps (Teams, Slack) read text/html for a
# formatted paste and ignore RTF entirely, so an RTF-only clipboard pastes
# into them as plain text stripped of markdown syntax (macOS synthesizes a
# plain-text flavor from the RTF on read). Office apps (Word, Mail, Notes)
# read RTF. Writing all three, in one atomic pasteboard transaction, covers
# both — a second `pbcopy` call can't do this, since each invocation clears
# the pasteboard before writing its one flavor.
#
# +hard_line_breaks: plain CommonMark treats a single newline as a soft wrap
# and joins the lines with a space, dropping the break entirely unless
# there's a blank line between paragraphs. Clipboard text (chat messages,
# addresses, anything not deliberately hard-wrapped prose) relies on every
# newline actually being a line break, so treat every one as such.
#
# +lists_without_preceding_blankline: without it, pandoc treats a "- item"
# line as a lazy continuation of the preceding paragraph (not a real list)
# unless a blank line separates them — measured: "So real internal FQDN:\n-
# foo\n- bar" produces one <p> with literal "-" text, not a <ul>. Chat text
# rarely has a blank line before a list.
#
# The generated HTML then goes through inline-html-styles.pl: pandoc's
# fragment output has no attributes on <p>/<ul>/<ol>/<li>, so spacing between
# blocks depends on the paste target's own default styles for those tags.
# Measured in Microsoft Teams: pasting several paragraphs and a list
# produced zero vertical gap between any of them, because Teams' rich-text
# editor resets those margins to 0. Explicit inline `style` margins survive
# paste sanitizers far more reliably than relying on the target's CSS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v pandoc >/dev/null 2>&1; then
  echo "ERROR: pandoc not found on PATH — install it with 'brew install pandoc'" >&2
  exit 2
fi

if ! command -v pbpaste >/dev/null 2>&1 || ! command -v osascript >/dev/null 2>&1 || ! command -v perl >/dev/null 2>&1; then
  echo "ERROR: pbpaste/osascript/perl not found on PATH — macOS only" >&2
  exit 3
fi

markdown=$(pbpaste)

if [ -z "$markdown" ]; then
  echo "ERROR: clipboard is empty" >&2
  exit 1
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

printf '%s' "$markdown" > "$workdir/input.md"

if ! pandoc -f markdown+hard_line_breaks+lists_without_preceding_blankline -t html "$workdir/input.md" -o "$workdir/raw.html" 2>"$workdir/err"; then
  echo "ERROR: pandoc HTML conversion failed: $(cat "$workdir/err")" >&2
  exit 4
fi
perl "$SCRIPT_DIR/inline-html-styles.pl" < "$workdir/raw.html" > "$workdir/output.html"

if ! pandoc -f markdown+hard_line_breaks+lists_without_preceding_blankline -t rtf -s "$workdir/input.md" -o "$workdir/output.rtf" 2>"$workdir/err"; then
  echo "ERROR: pandoc RTF conversion failed: $(cat "$workdir/err")" >&2
  exit 4
fi

if ! pandoc -f markdown+hard_line_breaks+lists_without_preceding_blankline -t plain "$workdir/input.md" -o "$workdir/output.txt" 2>"$workdir/err"; then
  echo "ERROR: pandoc plain-text conversion failed: $(cat "$workdir/err")" >&2
  exit 4
fi

if ! osascript -l JavaScript "$SCRIPT_DIR/write-clipboard.jxa.js" \
    "$workdir/output.html" "$workdir/output.rtf" "$workdir/output.txt" 2>"$workdir/err"; then
  echo "ERROR: writing the clipboard failed: $(cat "$workdir/err")" >&2
  exit 5
fi

html_bytes=$(wc -c < "$workdir/output.html" | tr -d ' ')
rtf_bytes=$(wc -c < "$workdir/output.rtf" | tr -d ' ')
echo "copied as rich text — ${html_bytes} bytes HTML, ${rtf_bytes} bytes RTF"
