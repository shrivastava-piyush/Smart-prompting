# Smart Prompting

A local prompt memory service for **MacBook and iPhone**. Save long,
carefully-crafted prompts once; recall them in one or two keystrokes when
driving Claude Code, Claude.ai, ChatGPT, or your own API scripts — no more
rewriting.

Everything is **free to run**: no paid Apple Developer account, no paid APIs
required. iCloud Drive does the cross-device sync.

## Highlights

- **Global hotkey popup** on macOS (⌥⌘P) — Spotlight-style search, Enter
  copies the selected prompt to the clipboard.
- **`sp` CLI** — paste prompts straight into Claude Code or any terminal
  agent (`sp find "..." | pbcopy`).
- **iPhone app** — browse, search, copy; Share Extension lets you save any
  selected text from Safari/Notes/ChatGPT; App Intents expose "Find Prompt"
  to Siri and Shortcuts.
- **Semantic + keyword search** — on-device embeddings (CoreML MiniLM, or
  Apple's built-in `NLEmbedding` as fallback) blended with SQLite FTS5 BM25.
- **Auto-title + auto-tag on save** — optional Claude Haiku call if you
  provide an API key; otherwise a fully offline heuristic.
- **Markdown-per-prompt source of truth** — your prompts live as plain
  `.md` files in iCloud Drive, so sync is conflict-safe and you can edit
  them in any text editor.

## Quick start (macOS CLI)

Prereqs: Xcode 15+ and a free Apple ID signed into Xcode.

```bash
git clone https://github.com/shrivastava-piyush/smart-prompting.git
cd smart-prompting
make cli                  # builds build/sp (universal)
sudo make install-cli     # → /usr/local/bin/sp
sp doctor                 # print paths, embedding backend, API-key status
```

## Everyday commands

```bash
sp add                    # paste a prompt; end with Ctrl-D
sp add -f prompt.md       # from a file
sp add -c                 # from the clipboard
sp ls                     # list all prompts, most-recently-used first
sp ls -t refactor         # filter by tag
sp find "code review"     # hybrid semantic + keyword search, pick a result
sp use my-slug \
    -v repo=foo/bar \
    -v goal=perf          # render + copy to clipboard
sp edit my-slug           # open the .md in $EDITOR
sp rm my-slug
sp set-key sk-ant-...     # (optional) enable AutoTag via Claude Haiku
```

### Using `sp` with Claude Code

```bash
sp find "bug triage" -n | claude    # pipe the top match straight in
sp use rust-refactor -p            # -p prints only (no clipboard)
```

## Mac hotkey app + iPhone app

Both are scaffolded as SwiftUI projects you open in Xcode. The full walkthrough
(entitlements, iCloud container ID, Gatekeeper bypass, AltStore sideload,
7-day profile refresh) is in **[`docs/install.md`](docs/install.md)**.

TL;DR:

```bash
make mac                              # DMG → drag to /Applications
make install-launchd                  # relaunch on login (hotkey always on)
DEVELOPMENT_TEAM=<your-team> make ios # produces build/SmartPrompting.ipa
```

## How it works

```
┌──────────────────────────────────────────────────────────┐
│              SmartPromptingCore (Swift SPM)              │
│  PromptStore · Search · Embeddings · AutoTag             │
│  TemplateEngine · ICloudSync · KeychainConfig            │
└────────────┬────────────────┬─────────────────┬──────────┘
             │                │                 │
     ┌───────▼──────┐  ┌──────▼────────┐  ┌─────▼────────┐
     │   sp  (CLI)  │  │ SmartPrompt   │  │ SmartPrompt  │
     │  macOS exec  │  │  .app (Mac)   │  │  iOS app     │
     │              │  │ menu bar +    │  │ list +       │
     │ add/find/use │  │ hotkey popup  │  │ Share Ext +  │
     │              │  │               │  │ Shortcuts    │
     └──────────────┘  └───────────────┘  └──────────────┘
```

Source of truth:

```
~/Library/Mobile Documents/iCloud~com~smartprompting/Documents/prompts/
    my-code-review-prompt.md       ← markdown + YAML frontmatter
    refactor-rust-function.md
```

Each device has a disposable SQLite index at
`~/Library/Application Support/SmartPrompting/index.sqlite` that's rebuilt
from the files on demand. Concurrent edits produce iCloud conflict copies —
no database-level merge required.

### Prompt file format

```markdown
---
id: 4a7c...
title: Code Review
tags: [pr, review, rust]
placeholders: [repo, focus]
created: 2026-04-15T10:00:00Z
updated: 2026-04-15T10:00:00Z
use_count: 3
last_used: 2026-04-15T12:30:00Z
---
Please review {{repo}} with a focus on {{focus}}.
Look for correctness, perf regressions, and missing tests.
```

`{{placeholders}}` are filled interactively by `sp use` and the GUI popups.

## Cost breakdown

- **Embeddings**: 100% on-device (CoreML MiniLM or `NLEmbedding`). $0.
- **Storage**: SQLite + iCloud Drive (free 5 GB tier is more than enough). $0.
- **AutoTag**: optional. Without an Anthropic API key the offline fallback
  runs. With one, each save costs ~$0.0001 with Claude Haiku — never a
  prerequisite.
- **Distribution**: ad-hoc codesigning on Mac, free personal provisioning on
  iOS. No $99/yr Apple Developer Program fee.

## Repository layout

```
Package.swift                        Swift Package: core + sp CLI + tests
Sources/SmartPromptingCore/          Cross-platform library
Sources/sp/                          macOS CLI (argument-parser)
Apps/SmartPromptingMac/              SwiftUI menu-bar + hotkey popup
Apps/SmartPromptingiOS/              SwiftUI list + Share Ext + App Intents
Resources/MiniLM.mlpackage           (built by scripts/build-coreml.py)
Tests/SmartPromptingCoreTests/       XCTest suite
scripts/
    build-cli.sh                     universal release binary + ad-hoc sign
    build-mac-app.sh                 archive → .app → DMG
    build-ios-ipa.sh                 archive → .ipa (free personal team)
    build-coreml.py                  one-time MiniLM → CoreML
    install-launchd.sh               login-item for the hotkey popup
Makefile                             make cli | mac | ios | release | test
docs/install.md                      step-by-step install walkthrough
```

## Development

```bash
swift build                 # builds core + sp
swift test                  # runs the XCTest suite
swift run sp doctor         # quick smoke test
```

Set `SMART_PROMPTING_DIR` to a throwaway path when testing locally so you
don't write into your real iCloud prompts:

```bash
SMART_PROMPTING_DIR=/tmp/sp swift run sp add -f fixtures/hello.md
```

## Contributing

Issues and PRs welcome. Keep pull requests focused and add tests in
`Tests/SmartPromptingCoreTests/` for any non-trivial core change.

## License

MIT — see [`LICENSE`](LICENSE).
