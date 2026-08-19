# AGENTS.md

Guidance for coding agents working on this repo.

## What this is

An Alfred 5 workflow that converts clipboard markdown to RTF in place, so
pasting elsewhere shows rendered rich text instead of raw markdown syntax.
One Bash script does the work; `info.plist` wires it into Alfred.

```
copyrmd  →  Keyword input  →  Run Script (copy-rendered-markdown.sh)  →  Notification
```

The script itself is source-agnostic: it only reads/writes the clipboard via
`pbpaste`/`pbcopy`, never anything Claude-Code- or app-specific. Don't
reintroduce a dependency on any particular clipboard producer.

## The conversion (important, non-obvious)

- `pandoc -f markdown -t rtf -s` — the `-s` (standalone) flag is required.
  Without it pandoc emits a headerless RTF fragment (starts at `{\pard …`
  with no `{\rtf1` header) that no app renders correctly.
- `pbcopy -Prefer rtf` — measured: this flag is a no-op on `pbcopy` (`man
  pbcopy` documents `-Prefer` for `pbpaste` only; `pbcopy` sets the RTF
  flavor by sniffing the `{\rtf1` header in the input). Kept anyway because
  it documents intent and is harmless — don't remove it thinking it's
  load-bearing, and don't rely on it actually doing anything either.
- Verifying the clipboard actually holds RTF: `pbpaste -Prefer rtf` does NOT
  reliably reflect this — measured returning 0 bytes even when RTF is
  genuinely on the clipboard. Use `osascript -e 'clipboard info'` instead;
  it reports `«class RTF », <bytes>` when RTF is present.

## Conventions

- Keep workflow logic in `scripts/copy-rendered-markdown.sh` as plain,
  testable Bash. Do not inline logic into `info.plist` — the plist only
  calls `./scripts/copy-rendered-markdown.sh`.
- After editing the script, lint it: `shellcheck scripts/*.sh build.sh
  make_release.sh` (CI runs the same check).
- After editing `info.plist`, validate it: `plutil -lint info.plist`.
- Repackage with `./build.sh` after any change to shipped files.
- Cut a release with `bash make_release.sh x.y.z` — it bumps `info.plist`'s
  version, builds the versioned `.alfredworkflow` + checksum in `dist/`, and
  prints the commit/push/`gh release create` commands to run manually. It
  never commits, tags, or publishes on its own.

## Files

- `scripts/copy-rendered-markdown.sh` — reads clipboard, converts, writes
  clipboard back. Exit codes: 1 empty clipboard, 2 pandoc missing, 3
  pbcopy/pbpaste missing, 4 pandoc conversion failed, 5 pbcopy failed.
- `info.plist` — Alfred workflow definition (objects, connections, config).
- `build.sh` — zips the workflow into `dist/*.alfredworkflow`.
- `make_release.sh` — bumps the version, builds the versioned artifact +
  checksum, and prints the release commands to run manually.
