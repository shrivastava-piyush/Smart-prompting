# Smart Prompting

A local prompt memory service for macOS and iOS. Save long, carefully-crafted
prompts once; recall them in one or two keystrokes when driving Claude Code,
ChatGPT, Claude.ai, or your own API scripts.

- **CLI** (`sp`) for terminal agents.
- **Global hotkey popup** (⌥⌘P) on macOS for browser/IDE chats.
- **iOS app** + Share Extension + App Intents (Siri/Shortcuts) for the phone.
- **Semantic search** via on-device embeddings (CoreML MiniLM, or Apple's
  built-in `NLEmbedding` as fallback) blended with SQLite FTS5.
- **Auto-title + auto-tag** on save, via Claude Haiku if you provide an API
  key; otherwise an offline heuristic.
- **iCloud Drive sync**: markdown-file-per-prompt is the source of truth, so
  concurrent edits stay conflict-safe.

Everything is free to run: no paid Apple Developer account, no paid APIs
required.

## Quick start

```
make cli               # builds build/sp
sudo make install-cli  # copies sp → /usr/local/bin
sp add                 # paste a prompt, Ctrl-D to save
sp find "code review"
```

Full install (including Mac hotkey app + iPhone) is in
[`docs/install.md`](docs/install.md).

## Layout

```
Sources/SmartPromptingCore/   cross-platform Swift library
Sources/sp/                   macOS CLI
Apps/SmartPromptingMac/       SwiftUI menu-bar + hotkey popup
Apps/SmartPromptingiOS/       SwiftUI list + Share Ext + App Intents
Resources/MiniLM.mlpackage    (optional) CoreML embedding model
scripts/                      build + install scripts
Tests/SmartPromptingCoreTests core unit tests
```

## License

MIT — see `LICENSE`.
