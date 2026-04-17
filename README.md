<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20iOS-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/swift-5.9+-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/cost-%240-brightgreen?style=flat-square" alt="Cost" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square" alt="License" />
</p>

<h1 align="center">Smart Prompting</h1>

<p align="center">
  <strong>Save prompts once. Recall them in two keystrokes.</strong><br/>
  A local prompt memory service for MacBook and iPhone — no server, no subscription, no rewriting.
</p>

---

## The Problem

You craft the same long, nuanced prompts over and over — code review guidelines,
refactoring instructions, bug triage templates — every time you open Claude Code,
Claude.ai, or ChatGPT. Copy-pasting from scattered notes doesn't scale.

## The Fix

**Smart Prompting** stores your prompts as plain Markdown files in iCloud Drive,
indexes them with on-device embeddings, and lets you recall any prompt in seconds:

| Surface | How |
|---|---|
| **Terminal** | `sp find "code review"` → copies to clipboard |
| **Any app** | Press **⌥⌘P** → Spotlight-style popup → Enter to copy |
| **iPhone** | Open the app → search → tap to copy; or ask Siri |

---

## Features at a Glance

| | Feature | Details |
|---|---|---|
| **🔍** | **Hybrid search** | On-device embeddings (CoreML MiniLM / Apple NLEmbedding) + SQLite FTS5. Finds prompts even with paraphrased queries. |
| **🏷** | **Smart auto-title** | Strips filler ("Please", "I want you to…"), extracts the action phrase, and title-cases it. Optionally calls Claude Haiku for richer titles + tags. |
| **📝** | **Templates** | `{{placeholder}}` syntax — filled interactively by the CLI or GUI before copying. |
| **☁️** | **iCloud sync** | One `.md` file per prompt. Edits sync across Mac and iPhone; conflicts produce sibling files, never corrupt a database. |
| **⌨️** | **Global hotkey** | macOS popup (⌥⌘P) with live search, keyboard navigation, and auto-paste. |
| **📱** | **iOS Share Extension** | Highlight text in Safari / Notes / ChatGPT → "Save to Smart Prompting". |
| **🗣** | **Siri & Shortcuts** | "Find prompt code review" from anywhere on your phone. |
| **💰** | **$0 to run** | No paid Apple Developer account. No required API keys. No server. |

---

## Quick Start

> **Prerequisites:** macOS 14+, Xcode 15+, free Apple ID signed into Xcode.

```bash
git clone https://github.com/shrivastava-piyush/smart-prompting.git
cd smart-prompting

make cli                  # build the universal CLI binary
sudo make install-cli     # install to /usr/local/bin/sp
sp doctor                 # verify setup
```

### Save your first prompt

```bash
# From a file
sp add -f my-review-prompt.md

# From the clipboard
sp add -c

# Type / paste interactively (end with Ctrl-D)
sp add
```

### Find and use it

```bash
sp find "review"          # search → pick from list → copied to clipboard
sp use code-review        # by slug — fills {{placeholders}} interactively
sp find "refactor" -n     # print the top hit to stdout (scriptable)
```

### Pipe into Claude Code

```bash
sp find "bug triage" -n | claude
sp use rust-refactor -v repo=my/proj -p | claude
```

---

## All CLI Commands

| Command | What it does |
|---|---|
| `sp add [-f FILE] [-c]` | Save a new prompt (file / clipboard / stdin). Auto-generates title, slug, and tags. |
| `sp find "query"` | Hybrid search. Pick a result, fills placeholders, copies to clipboard. |
| `sp find "query" -n` | Print top hit's body to stdout (no interactive picker). |
| `sp use <slug> [-v key=val …]` | Render a prompt by slug, filling `{{placeholders}}`. |
| `sp ls [--tag TAG]` | List all prompts, most-recently-used first. |
| `sp edit <slug>` | Open the `.md` file in `$EDITOR`. |
| `sp rm <slug>` | Delete a prompt (with confirmation). |
| `sp doctor` | Print storage path, embedding backend, API key status. |
| `sp set-key <key>` | Store an Anthropic API key in Keychain (enables richer AutoTag). |

---

## Mac App — Hotkey Popup

<table>
<tr>
<td width="50%">

**Install:**

```bash
make mac              # → build/SmartPrompting.dmg
make install-launchd  # auto-launch at login
```

First launch: right-click → Open (one-time Gatekeeper bypass).

</td>
<td width="50%">

**Use:**

1. Press **⌥⌘P** from anywhere.
2. Type a few words — results appear instantly.
3. **Enter** → copy to clipboard and dismiss.
4. If the prompt has `{{placeholders}}`, a form appears first.

</td>
</tr>
</table>

---

## iPhone App

<table>
<tr>
<td width="50%">

**Install (free, no Developer account):**

```bash
# Path A: Xcode direct (simplest)
# Connect iPhone, enable Developer Mode,
# select phone in Xcode, press ⌘R.

# Path B: AltStore sideload
DEVELOPMENT_TEAM=<id> make ios
# Drop .ipa into AltStore
```

</td>
<td width="50%">

**Features:**

- Browse + search your full prompt library.
- Tap to copy; long-press for placeholder form.
- **Share Extension** — save text from any app.
- **Siri / Shortcuts** — "Find prompt refactor".

</td>
</tr>
</table>

Full step-by-step in [`docs/install.md`](docs/install.md).

---

## How It Works

```
┌──────────────────────────────────────────────────────────────┐
│                 SmartPromptingCore (Swift SPM)                │
│  PromptStore · Search · Embeddings · AutoTag · TemplateEngine│
└────────────┬──────────────────┬──────────────────┬───────────┘
             │                  │                  │
     ┌───────▼──────┐   ┌──────▼────────┐  ┌──────▼───────┐
     │   sp  CLI    │   │  Mac App      │  │  iOS App     │
     │  (terminal)  │   │  (⌥⌘P popup)  │  │  (list/Siri) │
     └──────────────┘   └───────────────┘  └──────────────┘
```

### Storage: Markdown files in iCloud Drive

```
~/Library/Mobile Documents/iCloud~com~smartprompting/Documents/prompts/
├── code-review.md
├── rust-refactor.md
└── bug-triage-template.md
```

Each file is self-contained:

```yaml
---
id: 4a7c...
title: Review PR for Correctness and Performance   # ← auto-generated
tags: [review, code, pull-request]                  # ← auto-generated
placeholders: [repo, focus]                         # ← parsed from body
created: 2026-04-15T10:00:00Z
use_count: 3
---
Review {{repo}} with a focus on {{focus}}.
Check for correctness, perf regressions, and missing tests.
```

A **disposable SQLite index** on each device provides FTS5 keyword search and
embedding-based similarity. Delete it any time — it rebuilds from the `.md` files.

### Auto-Title (offline)

The local fallback doesn't just copy the first line. It:

1. Extracts the first imperative clause (before `.`, `:`, or newline).
2. Strips conversational filler ("Please", "I want you to", "Can you"…).
3. Truncates to ~60 chars on a word boundary.
4. Title-cases the result.

**"Please review this pull request for correctness and performance issues"**
→ **"Review This Pull Request for Correctness and Performance"**

**"I want you to refactor the authentication module to use JWT tokens"**
→ **"Refactor the Authentication Module to Use Jwt Tokens"**

With an optional Anthropic API key (`sp set-key`), Claude Haiku generates
even richer titles and 3–5 tags per prompt.

---

## Cost

| Component | Cost |
|---|---|
| Embeddings | **$0** — on-device (CoreML / NLEmbedding) |
| Storage & sync | **$0** — SQLite + iCloud Drive free tier |
| AutoTag (offline) | **$0** — built-in keyword extraction |
| AutoTag (Haiku) | **~$0.0001/save** — optional, not required |
| Distribution | **$0** — ad-hoc signing (Mac), free provisioning (iOS) |

---

## Project Structure

```
Package.swift                         Swift Package manifest
Sources/
├── SmartPromptingCore/               Cross-platform library
│   ├── PromptStore.swift             Markdown-backed store + SQLite index
│   ├── Search.swift                  Hybrid FTS5 + cosine ranker
│   ├── Embeddings.swift              CoreML / NLEmbedding / hashing fallback
│   ├── AutoTag.swift                 Smart title + tag generation
│   ├── TemplateEngine.swift          {{placeholder}} parse & render
│   ├── ICloudSync.swift              Ubiquity container resolution
│   └── ...
├── sp/
│   └── main.swift                    CLI (swift-argument-parser)
Apps/
├── SmartPromptingMac/                Menu bar + hotkey popup (SwiftUI)
├── SmartPromptingiOS/                List + Share Extension + App Intents
scripts/
├── build-cli.sh                      Universal binary + ad-hoc sign
├── build-mac-app.sh                  Archive → DMG
├── build-ios-ipa.sh                  Archive → IPA (free team)
├── build-coreml.py                   MiniLM → CoreML (one-time)
└── install-launchd.sh                Login item for hotkey
Tests/SmartPromptingCoreTests/        XCTest suite
Makefile                              make cli | mac | ios | test | release
```

---

## Development

```bash
swift build              # build core + CLI
swift test               # run test suite
swift run sp doctor      # smoke test

# Use a throwaway dir to avoid touching your real prompts:
SMART_PROMPTING_DIR=/tmp/sp swift run sp add -f fixtures/hello.md
```

## Contributing

Issues and PRs welcome. Add tests in `Tests/SmartPromptingCoreTests/` for
non-trivial core changes.

## License

MIT — see [`LICENSE`](LICENSE).
