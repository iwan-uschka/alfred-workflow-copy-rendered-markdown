#!/bin/bash
# Exercises the real script against the real clipboard and pandoc — no
# mocking of the conversion itself, since the bug this guards against
# (RTF-only clipboard, silently unreadable by Chromium/Electron apps) only
# shows up by inspecting actual pasteboard flavors, not by unit-testing
# pandoc's output in isolation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/copy-rendered-markdown.sh"

# This suite repeatedly overwrites the real clipboard via pbcopy — restore
# whatever was there before the run so it isn't left holding the last
# fixture's converted output as a routine surprise for the developer.
saved_clipboard=$(pbpaste 2>/dev/null || true)
restore_clipboard() {
  printf '%s' "$saved_clipboard" | pbcopy
}
trap restore_clipboard EXIT

pass=0
fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc — expected [$expected], got [$actual]"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc — expected to contain [$needle], got: $haystack"
  fi
}

refute_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail=$((fail + 1))
    echo "FAIL: $desc — expected NOT to contain [$needle], got: $haystack"
  else
    pass=$((pass + 1))
  fi
}

read_html_flavor() {
  osascript -l JavaScript -e '
ObjC.import("Cocoa");
var pb = $.NSPasteboard.generalPasteboard;
var data = pb.dataForType("public.html");
if (!data) { "" } else { $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js }
'
}

read_rtf_flavor() {
  osascript -l JavaScript -e '
ObjC.import("Cocoa");
var pb = $.NSPasteboard.generalPasteboard;
var data = pb.dataForType("public.rtf");
if (!data) { "" } else { $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js }
'
}

read_plain_flavor() {
  osascript -l JavaScript -e '
ObjC.import("Cocoa");
var pb = $.NSPasteboard.generalPasteboard;
var data = pb.dataForType("public.utf8-plain-text");
if (!data) { "" } else { $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js }
'
}

# --- success path: all three flavors land, HTML is well-formed and stripped of markdown syntax ---
printf '# Heading\n\n**bold text** and a list:\n\n- one\n- two\n' | pbcopy
out=$(bash "$SCRIPT")
code=$?
assert_eq "success exit code" "0" "$code"
assert_contains "success message mentions HTML" "$out" "HTML"
assert_contains "success message mentions RTF" "$out" "RTF"

info=$(osascript -e 'clipboard info')
assert_contains "clipboard has HTML flavor" "$info" "HTML"
assert_contains "clipboard has RTF flavor" "$info" "RTF"

html=$(read_html_flavor)
assert_contains "HTML flavor renders bold" "$html" "<strong>bold text</strong>"
assert_contains "HTML flavor renders list item" "$html" "<li"
assert_contains "HTML flavor list item has correct text" "$html" ">one</li>"
refute_contains "HTML flavor has no leftover markdown syntax" "$html" "**"
assert_contains "block tags carry inline spacing styles" "$html" "<p style="
assert_contains "list carries inline spacing styles" "$html" "<ul style="
assert_contains "list item carries inline spacing styles" "$html" "<li style=\"margin:0 0 4px 0\""

rtf=$(read_rtf_flavor)
assert_contains "RTF flavor renders bold" "$rtf" '{\b bold text}'
assert_contains "RTF flavor renders list bullet" "$rtf" '\bullet'
refute_contains "RTF flavor has no leftover markdown syntax" "$rtf" "**"

plain=$(read_plain_flavor)
assert_contains "plain-text flavor keeps the words" "$plain" "bold text"
refute_contains "plain-text flavor strips bold syntax" "$plain" "**bold text**"

# --- single newlines within a paragraph must survive as line breaks, not
# get collapsed into one joined line (plain CommonMark's default soft-wrap
# behavior — a real, reported bug) ---
printf 'Line one\nLine two\nLine three\n\nSecond paragraph.\n' | pbcopy
bash "$SCRIPT" >/dev/null
html=$(read_html_flavor)
assert_contains "single newlines become <br> in HTML" "$html" "Line one<br"
refute_contains "lines are not joined onto one line" "$html" "Line one Line two"
assert_contains "blank-line paragraph break still works" "$html" ">Second paragraph.</p>"

# --- a "- item" list directly after a paragraph line, with no blank line
# separating them, must still become a real <ul><li> list — not a lazy
# continuation of the paragraph with a literal "-" character (a real,
# reported bug: pandoc's default markdown reader requires a blank line
# before a list or it treats "- item" as plain paragraph text) ---
printf 'Some intro:\n- alpha\n- beta\n' | pbcopy
bash "$SCRIPT" >/dev/null
html=$(read_html_flavor)
assert_contains "list without preceding blank line becomes <ul>" "$html" "<ul"
assert_contains "first item renders as <li>" "$html" ">alpha</li>"
assert_contains "second item renders as <li>" "$html" ">beta</li>"
refute_contains "no literal dash-prefixed paragraph text" "$html" "- alpha"

# --- kitchen-sink fixture: headings, bold/italic/bold-italic, inline code,
# links, nested lists (both bullet and ordered), blockquotes, fenced code
# blocks, tables, horizontal rules and hard line breaks all in one document —
# broader coverage than the single-construct tests above, so a regression in
# a construct none of those touch (tables, blockquotes, nested lists, code
# blocks, links) still gets caught ---
pbcopy < "$SCRIPT_DIR/test/fixtures/kitchen-sink.md"
bash "$SCRIPT" >/dev/null
html=$(read_html_flavor)

assert_contains "kitchen sink: h1 renders" "$html" "<h1"
assert_contains "kitchen sink: h2 renders" "$html" "<h2"
assert_contains "kitchen sink: h3 renders" "$html" "<h3"
assert_contains "kitchen sink: bold renders" "$html" "<strong>bold</strong>"
assert_contains "kitchen sink: italic renders" "$html" "<em>italic</em>"
assert_contains "kitchen sink: bold-italic renders" "$html" "<strong><em>bold italic</em></strong>"
assert_contains "kitchen sink: inline code renders" "$html" "<code>inline code</code>"
assert_contains "kitchen sink: link renders" "$html" '<a href="https://example.com">link</a>'
assert_contains "kitchen sink: nested bullet list renders" "$html" ">top level"
assert_contains "kitchen sink: nested ordered list renders" "$html" "<ol"
assert_contains "kitchen sink: ordered list carries inline spacing styles" "$html" "<ol type=\"1\" style=\"margin:0 0 12px 0;padding-left:20px\""
assert_contains "kitchen sink: blockquote renders" "$html" "<blockquote>"
assert_contains "kitchen sink: fenced code block renders" "$html" "<pre><code>"
assert_contains "kitchen sink: table renders" "$html" "<table>"
assert_contains "kitchen sink: table header cell renders" "$html" "<th>Col A</th>"
assert_contains "kitchen sink: horizontal rule renders" "$html" "<hr"

refute_contains "kitchen sink: no leftover bold syntax" "$html" "**bold**"
# shellcheck disable=SC2016 # literal backticks, not meant to expand
refute_contains "kitchen sink: no leftover inline code syntax" "$html" '`inline code`'
refute_contains "kitchen sink: no leftover link syntax" "$html" "[link]"
refute_contains "kitchen sink: no leftover blockquote syntax" "$html" "> a blockquote"
refute_contains "kitchen sink: no leftover bullet syntax" "$html" "- top level"
refute_contains "kitchen sink: no leftover table pipe syntax" "$html" "| Col A | Col B |"
refute_contains "kitchen sink: no leftover hr syntax" "$html" "---"

# --- HTML-special characters in the source markdown must come out escaped,
# not literal — a literal "<" or "&" in the clipboard HTML flavor would be
# interpreted as a tag/entity start by the paste target instead of the text
# the user actually typed ---
printf '5 < 10 & 3 > 1\n' | pbcopy
bash "$SCRIPT" >/dev/null
html=$(read_html_flavor)
assert_contains "less-than is escaped" "$html" "&lt;"
assert_contains "ampersand is escaped" "$html" "&amp;"
assert_contains "greater-than is escaped" "$html" "&gt;"
refute_contains "no literal unescaped less-than from the input" "$html" "5 < 10"
refute_contains "no literal unescaped ampersand from the input" "$html" "10 & 3"

# --- empty clipboard ---
printf '' | pbcopy
out=$(bash "$SCRIPT" 2>&1)
code=$?
assert_eq "empty clipboard exit code" "1" "$code"
assert_contains "empty clipboard message" "$out" "empty"

# --- missing pandoc ---
printf '# x' | pbcopy
out=$(PATH=/usr/bin:/bin bash "$SCRIPT" 2>&1)
code=$?
assert_eq "missing pandoc exit code" "2" "$code"
assert_contains "missing pandoc message" "$out" "pandoc"

# --- missing pbpaste/osascript: a PATH sandbox with everything symlinked
# except those two, since real macOS binaries can't otherwise be "absent" ---
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"; restore_clipboard' EXIT
for dir in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*; do
    base=$(basename "$f")
    case "$base" in
      pbpaste|osascript) continue ;;
    esac
    [ -e "$sandbox/$base" ] && continue
    ln -s "$f" "$sandbox/$base" 2>/dev/null || true
  done
done
printf '# x' | pbcopy
out=$(PATH="$sandbox" bash "$SCRIPT" 2>&1)
code=$?
assert_eq "missing pbpaste/osascript exit code" "3" "$code"
assert_contains "missing pbpaste/osascript message" "$out" "pbpaste"

# --- missing perl only: same PATH-sandbox technique, but this time keep
# pbpaste/osascript and drop perl instead — it's checked in the same
# combined command as pbpaste/osascript, so a perl-only gap needs its own
# sandbox or it'd never be exercised ---
sandbox_no_perl=$(mktemp -d)
trap 'rm -rf "$sandbox" "$sandbox_no_perl"; restore_clipboard' EXIT
for dir in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*; do
    base=$(basename "$f")
    [ "$base" = "perl" ] && continue
    [ -e "$sandbox_no_perl/$base" ] && continue
    ln -s "$f" "$sandbox_no_perl/$base" 2>/dev/null || true
  done
done
printf '# x' | pbcopy
out=$(PATH="$sandbox_no_perl" bash "$SCRIPT" 2>&1)
code=$?
assert_eq "missing perl exit code" "3" "$code"
assert_contains "missing perl message" "$out" "perl"

# --- pandoc conversion failure: a stub `pandoc` earlier on PATH satisfies
# the `command -v pandoc` presence check but fails the conversion itself.
# Real pandoc practically never fails on arbitrary clipboard text, so this
# error path is otherwise unreachable from a test ---
stub_pandoc=$(mktemp -d)
trap 'rm -rf "$sandbox" "$sandbox_no_perl" "$stub_pandoc"; restore_clipboard' EXIT
printf '#!/bin/bash\necho "stub pandoc failure" >&2\nexit 1\n' > "$stub_pandoc/pandoc"
chmod +x "$stub_pandoc/pandoc"
printf '# x' | pbcopy
out=$(PATH="$stub_pandoc:$PATH" bash "$SCRIPT" 2>&1)
code=$?
assert_eq "pandoc conversion failure exit code" "4" "$code"
assert_contains "pandoc conversion failure message" "$out" "conversion failed"
assert_contains "pandoc conversion failure reports pandoc's stderr" "$out" "stub pandoc failure"

# --- clipboard write failure: same stub technique for `osascript`, so
# everything upstream succeeds and only the JXA pasteboard write fails ---
stub_osascript=$(mktemp -d)
trap 'rm -rf "$sandbox" "$sandbox_no_perl" "$stub_pandoc" "$stub_osascript"; restore_clipboard' EXIT
printf '#!/bin/bash\necho "stub osascript failure" >&2\nexit 1\n' > "$stub_osascript/osascript"
chmod +x "$stub_osascript/osascript"
printf '# x' | pbcopy
out=$(PATH="$stub_osascript:$PATH" bash "$SCRIPT" 2>&1)
code=$?
assert_eq "clipboard write failure exit code" "5" "$code"
assert_contains "clipboard write failure message" "$out" "writing the clipboard failed"
assert_contains "clipboard write failure reports the helper's stderr" "$out" "stub osascript failure"

echo ""
echo "${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
