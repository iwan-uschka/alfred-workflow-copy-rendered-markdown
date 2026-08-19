# Copy Rendered Markdown — Alfred Workflow

Convert whatever markdown is on the clipboard into rendered rich text (RTF),
in place — so pasting into Microsoft Teams, Word, Mail, Notes, Slack desktop,
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
pbpaste  →  pandoc -f markdown -t rtf -s  →  pbcopy -Prefer rtf
```

RTF is the clipboard flavor most rich-text targets (Teams, Word, Mail, Notes)
read for a formatted paste — more broadly supported here than fighting
`osascript`'s `set the clipboard to «data HTML...»` HTML-flavor route.

## Icon

`icon.png` is derived from the official
[Markdown mark](https://en.wikipedia.org/wiki/File:Markdown-mark.svg) by
Dustin Curtis (CC0 1.0, public domain), re-centered onto a square, padded
canvas to match a typical macOS/Alfred app-icon composition. Source SVGs are
in `assets/`.

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
  make_release.sh` (CI runs the same check).

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
