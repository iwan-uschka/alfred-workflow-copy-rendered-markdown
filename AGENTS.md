# AGENTS.md

Guidance for coding agents working on this repo.

## What this is

An Alfred 5 workflow that converts clipboard markdown to rendered rich text
in place, so pasting elsewhere shows real formatting instead of raw markdown
syntax. One Bash script does the work; `info.plist` wires it into Alfred.

```
copyrmd  →  Keyword input  →  Run Script (copy-rendered-markdown.sh)  →  Notification
```

The script itself is source-agnostic: it only reads/writes the clipboard,
never anything Claude-Code- or app-specific. Don't reintroduce a dependency
on any particular clipboard producer.

## The conversion (important, non-obvious)

**RTF alone is not enough — this was a real, reported bug** (fixed 2026;
see git history for `scripts/copy-rendered-markdown.sh`). Chromium/Electron
apps (Microsoft Teams, Slack) read `text/html` on paste and do not fall back
to RTF at all. An RTF-only clipboard pastes into them as plain text with the
markdown syntax already stripped — not literal `**bold**`, and not bold
either — because macOS synthesizes a plain-text flavor from the RTF's text
content when nothing else matches, silently discarding the formatting in the
process. This is easy to miss because RTF renders fine in Word/Mail/Notes/
TextEdit, so it looks correct until tested in an actual Chromium-based
target.

The fix: write **three** pasteboard flavors in one atomic transaction —
`public.html`, `public.rtf`, `public.utf8-plain-text` — via
`scripts/write-clipboard.jxa.js` (JXA + `NSPasteboard.setDataForType`).
`pbcopy` cannot do this: each invocation calls `clearContents` before writing
its one flavor, so calling it twice for two different flavors just makes the
second call win, not add to the first.

- `pandoc -f markdown -t html` (no `-s`) for the HTML flavor — a bare
  fragment (`<h1>…</h1><p>…</p>`), not a standalone document. A full
  `-s` document's `<style>`/`<head>` is unnecessary bytes on the clipboard
  and risky: some paste sanitizers handle a bare fragment more predictably
  than a full document.
- `pandoc -f markdown -t rtf -s` for the RTF flavor — here `-s` (standalone)
  IS required. Without it pandoc emits a headerless RTF fragment (starts at
  `{\pard …` with no `{\rtf1` header) that no app renders correctly.
- `pandoc -f markdown -t plain` for the plain-text flavor — human-readable
  prose with markdown syntax already stripped, so a plain-text-only paste
  target still gets something reasonable instead of literal `**`/`-`/`#`
  characters.
- All three use
  `-f markdown+hard_line_breaks+lists_without_preceding_blankline`, not
  plain `markdown` — two separate real, reported bugs:
  - `+hard_line_breaks`: plain CommonMark treats a single `\n` as a soft
    wrap and joins the two lines with a space, dropping the break entirely
    unless there's a blank line between them (`pandoc -f markdown -t html`
    on `"Line one\nLine two"` produces `<p>Line one Line two</p>`, not two
    lines). Clipboard text almost never comes hard-wrapped as deliberate
    prose — chat messages, addresses, anything typed with real Enter
    presses — so every newline needs to survive as an actual line break
    (`<br>` in HTML, `\line` in RTF). A blank line still starts a genuinely
    new paragraph either way.
  - `+lists_without_preceding_blankline`: without it, pandoc's markdown
    reader treats a `- item` line directly after a paragraph line (no
    blank line between them) as a *lazy continuation* of that paragraph,
    not the start of a list — measured: `"So real internal FQDN:\n- foo\n-
    bar"` produces one `<p>` containing the literal text `- foo - bar`,
    with no `<ul>` at all, not even one with a wrong bullet style. This is
    a pandoc-specific default (not universal CommonMark behavior) and is
    easy to miss in testing if your test fixtures always put a blank line
    before a list out of habit — real chat text usually doesn't.
- Verifying flavors landed: `osascript -e 'clipboard info'` reports each
  present type and its byte count (e.g. `«class HTML», 113, «class RTF »,
  779, «class utf8», 44, string, 44`). To verify *content*, not just
  presence, read the type directly:
  `osascript -l JavaScript -e 'ObjC.import("Cocoa"); $.NSString.alloc.initWithDataEncoding($.NSPasteboard.generalPasteboard.dataForType("public.html"), $.NSUTF8StringEncoding).js'`.
  `pbpaste -Prefer rtf`/`-Prefer txt` do NOT reliably reflect what's on the
  pasteboard — measured returning 0 bytes for a flavor that `clipboard info`
  confirmed was genuinely present.
- `pbcopy -Prefer rtf` (used by the pre-fix, RTF-only version of this
  script) is a no-op on `pbcopy` — `man pbcopy` documents `-Prefer` for
  `pbpaste` only; `pbcopy` sets the RTF flavor by sniffing the `{\rtf1`
  header in the input regardless of the flag.
**Block spacing collapses in paste targets with their own editor CSS — a
third real, reported bug.** pandoc's HTML fragment emits bare
`<p>`/`<ul>`/`<ol>`/`<li>` with no attributes, so vertical spacing between
blocks depends entirely on the paste target's default styles for those
tags. Measured pasting into Microsoft Teams: several paragraphs and a list
landed with zero gap between any of them, because Teams' rich-text editor
resets those margins to 0 — confirmed by simulating the same reset
(`p, ul, li { margin: 0 }`) in a local browser page and pasting our
generated HTML into it. `<style>` blocks and CSS classes don't survive most
paste sanitizers (nothing in the target's own stylesheet resolves a class
name that isn't defined there), so the fix is `scripts/inline-html-styles.pl`:
a stdin→stdout Perl filter that injects an inline `style="margin:…"`
attribute directly onto each `<p>`/`<ul>`/`<ol>`/`<li>` tag in the pandoc
HTML output before it's written to the clipboard. Inline `style` attributes
survive sanitizers where classes and stylesheets don't. Pipe pandoc's HTML
output through it as a separate step (write to a temp file, then filter) —
don't chain them in one pipeline under `set -o pipefail`, since the
pipeline's exit status would then reflect the filter's exit code, not
pandoc's, silently masking a pandoc conversion failure.

- A fully automated "does this actually render in a real Chromium/Electron
  app" test was attempted and abandoned: Chrome blocks scripted
  `document.execCommand('paste')`, CDP-dispatched synthetic `Meta+V` key
  events did not trigger the browser's native paste handler in this
  environment (plain unmodified keys worked fine — only the modifier
  combo silently did nothing), and routing a real OS-level ⌘V through
  `System Events` requires Accessibility permission for UI scripting
  (`osascript`), which was not granted and isn't something to request just
  for a test run. The pasteboard-flavor + content checks in
  `test/copy-rendered-markdown.test.sh` are the automatable proxy; an actual
  paste into Teams (or any Chromium app) still needs a manual check after
  changing the conversion logic.

## Conventions

- Keep workflow logic in `scripts/copy-rendered-markdown.sh` as plain,
  testable Bash. Do not inline logic into `info.plist` — the plist only
  calls `./scripts/copy-rendered-markdown.sh`.
- After editing the script, lint it: `shellcheck scripts/*.sh build.sh
  make_release.sh` (CI runs the same check).
- After editing `info.plist`, validate it: `plutil -lint info.plist`.
- After editing conversion logic, run `bash
  test/copy-rendered-markdown.test.sh` — and sanity-check the test itself
  catches a regression by reverting the change under test and confirming it
  now fails (that's how the original RTF-only bug was confirmed fixed).
- Repackage with `./build.sh` after any change to shipped files.
- Cut a release with `bash make_release.sh x.y.z` — it bumps `info.plist`'s
  version, builds the versioned `.alfredworkflow` + checksum in `dist/`, and
  prints the commit/push/`gh release create` commands to run manually. It
  never commits, tags, or publishes on its own.

## Files

- `scripts/copy-rendered-markdown.sh` — reads clipboard, converts via
  pandoc, writes clipboard back via the JXA helper. Exit codes: 1 empty
  clipboard, 2 pandoc missing, 3 pbpaste/osascript/perl missing, 4 pandoc
  conversion failed, 5 the JXA clipboard write failed.
- `scripts/write-clipboard.jxa.js` — the multi-flavor pasteboard writer
  (see "The conversion" above). Takes three file paths as argv: HTML, RTF,
  plain text.
- `scripts/inline-html-styles.pl` — stdin→stdout filter that injects inline
  `style="margin:…"` onto `<p>`/`<ul>`/`<ol>`/`<li>` in pandoc's HTML
  output (see "The conversion" above). No dependencies beyond core Perl.
- `test/copy-rendered-markdown.test.sh` — runs the real script against the
  real clipboard/pandoc; no mocking. Self-contained; `bash
  test/copy-rendered-markdown.test.sh` from anywhere. Includes a
  kitchen-sink section (`test/fixtures/kitchen-sink.md`) covering headings,
  bold/italic/bold-italic, inline code, links, nested bullet and ordered
  lists, blockquotes, fenced code blocks, tables and horizontal rules in one
  document — broader coverage than the targeted single-construct tests, so a
  regression in a construct none of those touch (tables, blockquotes, nested
  lists, code blocks, links) still gets caught. Also covers: RTF and
  plain-text flavor content (not just presence — the RTF flavor is checked
  for a `{\b ...}` run and a `\bullet` marker, the plain-text flavor for
  stripped-but-legible words), HTML-escaping of `<`/`&`/`>` in the source
  markdown, and a perl-missing exit path (sandboxed separately from the
  pbpaste/osascript sandbox, since perl is checked in the same combined
  command and a shared sandbox would never isolate it).
- `test/fixtures/kitchen-sink.md` — the broad markdown fixture above.
- `info.plist` — Alfred workflow definition (objects, connections, config).
- `build.sh` — zips the workflow into `dist/*.alfredworkflow`.
- `make_release.sh` — bumps the version, builds the versioned artifact +
  checksum, and prints the release commands to run manually.
- `icon.png` — bundled automatically by `build.sh` if present (Alfred reads
  it from the bundle root by convention, no `info.plist` key needed).
  Derived from the official Markdown mark (CC0) by Dustin Curtis
  (https://en.wikipedia.org/wiki/File:Markdown-mark.svg), re-centered onto a
  padded square canvas to match a typical app-icon composition.
