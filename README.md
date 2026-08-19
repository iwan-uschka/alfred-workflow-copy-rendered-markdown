# Copy Rendered Markdown — Alfred Workflow

Convert whatever markdown is on the clipboard into rendered rich text, in
place — so pasting into Microsoft Teams, Word, Mail, Notes, Slack desktop,
etc. shows real **bold**, lists and headings instead of raw `**markdown**`
syntax.

Source-agnostic: the markdown can come from anywhere — an editor, a browser,
a chat tool, [Claude Code's](https://claude.com/product/claude-code) `/copy`
— this workflow only ever looks at the clipboard.

## Install

1. Download `Copy-Rendered-Markdown.alfredworkflow` (from Releases, or run
   `./build.sh` to package it into `dist/`).
2. Double-click it to import into Alfred (requires the Alfred Powerpack).
3. Install [pandoc](https://pandoc.org/): `brew install pandoc`.

## Usage

```
copyrmd
```

1. Copy some markdown to the clipboard, from anywhere.
2. Trigger Alfred and type `copyrmd`.
3. Press <kbd>Enter</kbd>. A notification confirms the byte count, or reports
   an error (e.g. pandoc missing, clipboard empty).
4. Paste anywhere that accepts rich text.

Want a hotkey instead of typing the keyword? Open the workflow in Alfred and
add a **Hotkey** trigger connected to the same Run Script action.

## How it works

`scripts/copy-rendered-markdown.sh`:

```
pbpaste  →  pandoc (html + rtf + plain)  →  write-clipboard.jxa.js
```

It writes **three** pasteboard flavors at once — `public.html`, `public.rtf`,
`public.utf8-plain-text` — via a small JXA helper
(`scripts/write-clipboard.jxa.js`) using `NSPasteboard` directly. RTF alone
is not enough: Chromium/Electron apps (Teams, Slack) read `text/html` for a
formatted paste and ignore RTF entirely, so an RTF-only clipboard pastes into
them as plain text stripped of markdown syntax — macOS synthesizes a
plain-text flavor from the RTF on read, which is what you get instead.
Office apps (Word, Mail, Notes) read RTF. Writing both, in one atomic
pasteboard transaction, covers both — `pbcopy` can't do this: each
invocation clears the pasteboard before writing its one flavor, so a second
`pbcopy` call for a different flavor wipes the first instead of adding to
it.

Conversion uses `-f markdown+hard_line_breaks+lists_without_preceding_blankline`,
not plain `markdown`:

- `+hard_line_breaks` — otherwise a single newline gets treated as an
  insignificant soft wrap and the lines get joined with a space instead of
  staying on separate lines. Clipboard text is almost never deliberately
  hard-wrapped prose, so every newline is treated as a real line break.
- `+lists_without_preceding_blankline` — otherwise a `- item` list right
  after a paragraph line, with no blank line before it, gets treated as
  plain paragraph text (literal `-` character, no real list) instead of a
  `<ul>`. Chat text rarely has a blank line before a list.

The generated HTML then goes through `scripts/inline-html-styles.pl`, which
adds explicit `margin` styles to `<p>`/`<ul>`/`<ol>`/`<li>`. Without it,
spacing between blocks depends on the paste target's own default styles for
those tags — measured pasting into Microsoft Teams: several paragraphs and
a list landed with **zero** vertical gap between any of them, because
Teams' rich-text editor resets those margins to 0. Inline `style`
attributes survive paste sanitizers far more reliably than relying on the
target's CSS.

## Icon

`icon.png` is derived from the official
[Markdown mark](https://en.wikipedia.org/wiki/File:Markdown-mark.svg) by
Dustin Curtis (CC0 1.0, public domain), re-centered onto a square, padded
canvas to match a typical macOS/Alfred app-icon composition.

## Development

- Workflow logic lives entirely in `scripts/copy-rendered-markdown.sh` — plain
  Bash, testable from the command line:
  ```bash
  printf '# Heading\n\n**bold** and a list:\n\n- one\n- two\n' | pbcopy
  ./scripts/copy-rendered-markdown.sh
  ```
- `info.plist` wires it up: Keyword (`copyrmd`) → Run Script → Notification.
- `./build.sh` packages the `.alfredworkflow`.
- After editing `info.plist`, validate it: `plutil -lint info.plist`.
- After editing the script, lint it: `shellcheck scripts/*.sh build.sh
  make_release.sh test/*.test.sh`.
- Run the test suite: `bash test/copy-rendered-markdown.test.sh`. It runs
  the real script against the real clipboard and pandoc (no mocking — every
  bug found so far only showed up by inspecting actual pasteboard flavors
  and content, not by unit-testing pandoc's output in isolation) and
  checks: all three flavors land, the HTML flavor is well-formed, free of
  leftover markdown syntax, has real `<ul>/<li>` lists (even without a
  blank line before them) and real `<br>` line breaks, block tags carry
  inline spacing styles, and the error paths (empty clipboard, missing
  `pandoc`, missing `pbpaste`/`osascript`) exit with the documented codes.
  A kitchen-sink fixture (`test/fixtures/kitchen-sink.md`) adds broader
  coverage — headings, nested lists, blockquotes, fenced code blocks,
  tables, links, horizontal rules — in one document. Also checked: RTF and
  plain-text flavor content (not just that the flavors are present), HTML
  escaping of `<`/`&`/`>`, and a perl-missing error path.
- No automated test exercises an actual paste into a real Chromium/Electron
  app (Teams itself, or even a local `contenteditable` page): Chrome blocks
  scripted `document.execCommand('paste')`, and simulating a real OS-level
  ⌘V requires Accessibility permission for UI scripting, which isn't
  something to grant just for a test run. The pasteboard-flavor/content
  checks above are the automatable proxy for "will this render correctly
  elsewhere" — verify an actual Teams paste by hand after changing the
  conversion logic.

## Publishing a release

```bash
bash make_release.sh 1.2.0
```

This bumps the version in `info.plist`, builds
`dist/Copy-Rendered-Markdown-v1.2.0.alfredworkflow` plus a `.sha256` checksum,
and prints the exact `git commit`/`push` and `gh release create --generate-notes`
commands to run by hand. It does not commit, tag, or publish anything itself.

## License

MIT — see [`LICENSE`](LICENSE).
