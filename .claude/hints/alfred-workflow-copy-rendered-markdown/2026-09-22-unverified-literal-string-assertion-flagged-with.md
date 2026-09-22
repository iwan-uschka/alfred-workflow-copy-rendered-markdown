# Unverified literal-string assertion flagged without running the test

- **Pattern:** A test asserts an exact literal substring of third-party tool output (e.g. pandoc's RTF), and the finding claims the literal is unverified/risky without executing the tool to check.
- **The finding claimed:** The RTF hyperlink-field assertion's exact literal string (`HYPERLINK "https://example.com/ISSUE-1"`) could not be confirmed against real pandoc output during review, so it might cause a false test failure. (`test/copy-rendered-markdown.test.sh:187`)
- **Why that was wrong:** The literal substring was verified against real pandoc RTF output and is exactly present; the assertion is already correct as written, so there is nothing to fix.
- **Before raising this again, verify:** Run the test file directly against the real toolchain (`bash test/copy-rendered-markdown.test.sh`) before flagging an assertion's literal as unverified — this repo's own convention (`AGENTS.md`: "runs the real script against the real clipboard/pandoc; no mocking") makes that check cheap and authoritative.

_fix-jira-code-link-strip, 2026-09-22_
