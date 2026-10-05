# AGENTS.md

Guidance for coding agents working on this repo.

## What this is

An Alfred 5 workflow that converts clipboard markdown to rendered rich text
in place, so pasting elsewhere shows real formatting instead of raw markdown
syntax. One Bash script does the work; `info.plist` wires it into Alfred.

```
copyrmd  →  Keyword input  →  Run Script (copy-rendered-markdown.sh)  →  Notification
```

The script is source-agnostic. It only reads and writes the clipboard,
never anything specific to Claude Code or another app. Don't reintroduce a
dependency on any particular clipboard producer.

## The conversion (important, non-obvious)

**RTF alone is not enough. This was a real, reported bug** (fixed 2026;
see git history for `scripts/copy-rendered-markdown.sh`). Chromium/Electron
apps (Microsoft Teams, Slack) read `text/html` on paste and do not fall back
to RTF at all. An RTF-only clipboard pastes into them as plain text with the
markdown syntax already stripped. The result is neither literal `**bold**`
nor bold, because macOS synthesizes a plain-text flavor from the RTF's text
content when nothing else matches and discards the formatting in the
process. This is easy to miss because RTF renders fine in Word, Mail, Notes
and TextEdit, so it looks correct until tested in a Chromium-based target.

The fix writes **three** pasteboard flavors in one atomic transaction,
`public.html`, `public.rtf` and `public.utf8-plain-text`, via
`scripts/write-clipboard.jxa.js` (JXA + `NSPasteboard.setDataForType`).
`pbcopy` cannot do this. Each invocation calls `clearContents` before writing
its one flavor, so calling it twice for two different flavors makes the
second call win instead of adding to the first.

- `pandoc -f markdown -t html` (no `-s`) produces the HTML flavor as a bare
  fragment (`<h1>…</h1><p>…</p>`), not a standalone document. A full `-s`
  document's `<style>`/`<head>` adds unneeded bytes to the clipboard and
  carries a risk: some paste sanitizers handle a bare fragment more
  predictably than a full document.
- `pandoc -f markdown -t rtf -s` produces the RTF flavor, and here `-s`
  (standalone) IS required. Without it pandoc emits a headerless RTF
  fragment (starts at `{\pard …` with no `{\rtf1` header) that no app
  renders correctly.
- `pandoc -f markdown -t plain` produces the plain-text flavor. It is
  readable prose with markdown syntax already stripped, so a plain-text-only
  paste target still gets something reasonable instead of literal
  `**`/`-`/`#` characters.
- All three use
  `-f markdown+hard_line_breaks+lists_without_preceding_blankline`, not
  plain `markdown`. Each extension fixes a separate real, reported bug:
  - `+hard_line_breaks`: plain CommonMark treats a single `\n` as a soft
    wrap and joins the two lines with a space. The break disappears unless
    a blank line separates them (`pandoc -f markdown -t html` on
    `"Line one\nLine two"` produces `<p>Line one Line two</p>`, not two
    lines). Clipboard text almost never comes hard-wrapped as deliberate
    prose. Chat messages, addresses and anything typed with real Enter
    presses need every newline to survive as an actual line break (`<br>`
    in HTML, `\line` in RTF). A blank line still starts a new paragraph
    either way.
  - `+lists_without_preceding_blankline`: without it, pandoc's markdown
    reader treats a `- item` line directly after a paragraph line (no
    blank line between them) as a *lazy continuation* of that paragraph,
    not the start of a list. Measured: `"So real internal FQDN:\n- foo\n-
    bar"` produces one `<p>` containing the literal text `- foo - bar`,
    with no `<ul>` at all, not even one with a wrong bullet style. This is
    a pandoc-specific default (not universal CommonMark behavior). It is
    easy to miss in testing if your fixtures always put a blank line
    before a list out of habit. Real chat text usually doesn't.
- To verify the flavors landed, run `osascript -e 'clipboard info'`. It
  reports each present type and its byte count (e.g. `«class HTML», 113,
  «class RTF », 779, «class utf8», 44, string, 44`). To verify *content*,
  not only presence, read the type directly:
  `osascript -l JavaScript -e 'ObjC.import("Cocoa"); $.NSString.alloc.initWithDataEncoding($.NSPasteboard.generalPasteboard.dataForType("public.html"), $.NSUTF8StringEncoding).js'`.
  `pbpaste -Prefer rtf`/`-Prefer txt` do NOT reliably reflect what's on the
  pasteboard. They were measured returning 0 bytes for a flavor that
  `clipboard info` confirmed was present.
- `pbcopy -Prefer rtf` (used by the pre-fix, RTF-only version of this
  script) is a no-op on `pbcopy`. `man pbcopy` documents `-Prefer` for
  `pbpaste` only; `pbcopy` sets the RTF flavor by sniffing the `{\rtf1`
  header in the input regardless of the flag.

**Block spacing collapses in paste targets with their own editor CSS. This
was a third real, reported bug.** pandoc's HTML fragment emits bare
`<p>`/`<ul>`/`<ol>`/`<li>` with no attributes, so vertical spacing between
blocks depends entirely on the paste target's default styles for those
tags. Measured pasting into Microsoft Teams: several paragraphs and a list
landed with zero gap between any of them, because Teams' rich-text editor
resets those margins to 0. Simulating the same reset
(`p, ul, li { margin: 0 }`) in a local browser page and pasting our
generated HTML into it confirmed this. `<style>` blocks and CSS classes
don't survive most paste sanitizers (nothing in the target's own stylesheet
resolves a class name that isn't defined there). The fix is
`scripts/inline-html-styles.pl`, a stdin-to-stdout Perl filter that injects
an inline `style="margin:…"` attribute directly onto each
`<p>`/`<ul>`/`<ol>`/`<li>` tag in the pandoc HTML output before the script
writes it to the clipboard. Inline `style` attributes survive sanitizers
where classes and stylesheets don't. Pipe pandoc's HTML output through it as
a separate step (write to a temp file, then filter). Don't chain them in one
pipeline under `set -o pipefail`. The pipeline's exit status would then
reflect the filter's exit code instead of pandoc's, which hides a pandoc
conversion failure.

- A fully automated "does this actually render in a real Chromium/Electron
  app" test was attempted and abandoned. Chrome blocks scripted
  `document.execCommand('paste')`. CDP-dispatched synthetic `Meta+V` key
  events did not trigger the browser's native paste handler in this
  environment (plain unmodified keys worked fine, only the modifier combo
  did nothing). Routing a real OS-level ⌘V through `System Events` requires
  Accessibility permission for UI scripting (`osascript`), which was not
  granted and isn't worth requesting for a test run. The pasteboard-flavor
  and content checks in `test/copy-rendered-markdown.test.sh` are the
  automatable proxy. An actual paste into Teams (or any Chromium app) still
  needs a manual check after changing the conversion logic.

**A link whose label is also code-formatted loses its href when pasted into
Jira or Confluence. This was a fourth real, reported bug.** Source markdown
like `` [`ISSUE-1`](url) `` converts to
`<a href="url"><code>ISSUE-1</code></a>` in the HTML flavor, verified with
`osascript -l JavaScript -e
'ObjC.import("Cocoa");
$.NSString.alloc.initWithDataEncoding($.NSPasteboard.generalPasteboard.dataForType("public.html"),
$.NSUTF8StringEncoding).js'` right after running the script. Atlassian's
editor (the ADF schema behind both Jira and Confluence) treats the `code`
mark as mutually exclusive with the `link` mark. Its paste handler resolves
that conflict by keeping the text and dropping the link, not by keeping the
link and dropping the code style. Confirmed 2026-09-22 by pasting the
identical generated HTML into both a real Jira comment box (link gone,
plain text left) and Microsoft Teams (link intact). The clipboard content
was the same and the result differed, so this is an ADF-side quirk, not
something wrong with the generated HTML.

The fix: `scripts/inline-html-styles.pl` also unwraps any `<code>` nested
inside an `<a>`, so `<a href="url"><code>ISSUE-1</code></a>` becomes
`<a href="url">ISSUE-1</a>`. It leaves the surrounding `<em>` and
everything else untouched. This only touches the HTML flavor. RTF stays as
is, since Word and Notes have no such mark-exclusivity rule and the code
styling there does no harm. The filter now slurps stdin in one read
(`local $/`) instead of processing line by line, because pandoc wraps long
lines mid-tag. A single `<a href="...">` can land split across two lines,
which a line-by-line regex would never see as one match. Inside the
replacement block, capture `$1`/`$2`/`$3` into named variables *before*
running the inner `<code>`-stripping substitution. That inner `s///` is
itself a regex match and clobbers `$1`/`$2`/`$3` from the outer match if
you reference them after it runs. The result drops the link's `href`
entirely instead of only failing to strip the `<code>`.

## Conventions

- Keep workflow logic in `scripts/copy-rendered-markdown.sh` as plain,
  testable Bash. Do not inline logic into `info.plist`. The plist only
  calls `./scripts/copy-rendered-markdown.sh`.
- After editing the script, lint it: `shellcheck scripts/*.sh build.sh
  make_release.sh test/*.test.sh`.
- After editing `info.plist`, validate it: `plutil -lint info.plist`.
- After editing conversion logic, run `bash
  test/copy-rendered-markdown.test.sh`. Also check that the test catches a
  regression: revert the change under test and confirm the test now fails
  (that's how the original RTF-only bug was confirmed fixed).
- Repackage with `./build.sh` after any change to shipped files.
- Cut a release with `bash make_release.sh x.y.z`. It bumps `info.plist`'s
  version, builds the versioned `.alfredworkflow` + checksum in `dist/`, and
  prints the commit/push/`gh release create` commands to run manually. It
  never commits, tags, or publishes on its own.

## Files

- `scripts/copy-rendered-markdown.sh` reads the clipboard, converts via
  pandoc, and writes the clipboard back via the JXA helper. Exit codes: 1
  empty clipboard, 2 pandoc missing, 3 pbpaste/osascript/perl missing, 4
  pandoc conversion failed, 5 the JXA clipboard write failed, 6
  `inline-html-styles.pl` failed.
- `scripts/write-clipboard.jxa.js` is the multi-flavor pasteboard writer
  (see "The conversion" above). It takes three file paths as argv: HTML,
  RTF, plain text. Its one independently testable failure path is a flavor
  file that can't be read (covered in `test/copy-rendered-markdown.test.sh`,
  which runs the real script directly instead of stubbing osascript). The
  three `setDataForType` calls (public.html/public.rtf/public.utf8-plain-text)
  are not independently testable. `setDataForType` is an in-process Cocoa
  framework call, not a separate executable on PATH, so it can't be stubbed
  to fail on demand, and it practically never fails for well-formed Data
  with a standard UTI string.
- `scripts/inline-html-styles.pl` is a stdin-to-stdout filter that injects
  inline `style="margin:…"` onto `<p>`/`<ul>`/`<ol>`/`<li>` in pandoc's HTML
  output and unwraps any `<code>` nested inside an `<a>` link (see "The
  conversion" above). It needs nothing beyond core Perl.
- `test/copy-rendered-markdown.test.sh` runs the real script against the
  real clipboard and pandoc, with no mocking. It is self-contained; run
  `bash test/copy-rendered-markdown.test.sh` from anywhere. It includes a
  kitchen-sink section (`test/fixtures/kitchen-sink.md`) covering headings,
  bold/italic/bold-italic, inline code, links, nested bullet and ordered
  lists, blockquotes, fenced code blocks, tables and horizontal rules in one
  document. That section covers more than the targeted single-construct
  tests, so it still catches a regression in a construct none of those
  touch (tables, blockquotes, nested lists, code blocks, links). The test
  also covers:
  - RTF and plain-text flavor content, not only presence. It checks the RTF
    flavor for a `{\b ...}` run and a `\bullet` marker, and the plain-text
    flavor for stripped but legible words.
  - HTML-escaping of `<`/`&`/`>` in the source markdown.
  - The code-in-link unwrap. A code-formatted link label keeps its `href`
    in the HTML flavor and keeps its RTF hyperlink field.
  - A perl-missing exit path, sandboxed separately from the
    pbpaste/osascript sandbox. The script checks perl in the same combined
    command, so a shared sandbox would never isolate it.
  - `write-clipboard.jxa.js`'s missing-flavor-file exit path. The script
    reads a deleted flavor file via `NSData.dataWithContentsOfFile`, which
    bridges a failed read to an ObjC nil that's truthy in JS. The test only
    stays green if the script checks it with `.isNil()` instead of a bare
    falsy check.
- `test/fixtures/kitchen-sink.md` is the broad markdown fixture above.
- `info.plist` is the Alfred workflow definition (objects, connections,
  config).
- `build.sh` zips the workflow into `dist/*.alfredworkflow`.
- `make_release.sh` bumps the version, builds the versioned artifact +
  checksum, and prints the release commands to run manually.
- `icon.png` is bundled automatically by `build.sh` if present (Alfred reads
  it from the bundle root by convention, no `info.plist` key needed). It is
  derived from the official Markdown mark (CC0) by Dustin Curtis
  (https://en.wikipedia.org/wiki/File:Markdown-mark.svg), re-centered onto a
  padded square canvas to match a typical app-icon composition.
