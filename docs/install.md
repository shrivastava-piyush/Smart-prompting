# Install Smart Prompting

Everything below is **free**. No paid Apple Developer Program ($99/yr) required.
The trade-off is that macOS Gatekeeper warns on first launch and iOS
provisioning profiles expire every 7 days — both easy to work around.

## Prerequisites (one-time, on your Mac)

1. Install Xcode 15+ from the App Store and run `xcode-select --install`.
2. Sign into Xcode with your free Apple ID:
   Xcode → Settings → Accounts → add your Apple ID.
3. Note your personal `Team ID` from the Accounts pane — you'll export it as
   `DEVELOPMENT_TEAM` when building the iOS app.
4. (Optional) `brew install create-dmg` for nicer Mac DMGs.
5. (Optional, for best-quality embeddings) build the CoreML model once:
   ```
   python3 -m venv .venv && source .venv/bin/activate
   pip install coremltools torch transformers
   python3 scripts/build-coreml.py
   git add Resources/MiniLM.mlpackage && git commit -m "build: MiniLM"
   ```
   Without this step the app still works — it falls back to Apple's built-in
   `NLEmbedding.sentenceEmbedding(.english)`.

## Clone & build

```
git clone https://github.com/shrivastava-piyush/smart-prompting.git
cd smart-prompting
make cli          # builds build/sp
swift test        # runs the core test suite
```

## macOS — CLI only (terminal users)

```
make install-cli
sp doctor
```

`sp doctor` prints the prompts directory (iCloud Drive if available), the
embedding backend in use, and whether an API key is configured.

Usage:

```
sp add               # paste a prompt, end with Ctrl-D
sp add -f prompt.md  # from a file
sp add -c            # from the clipboard
sp ls
sp find "code review"
sp use my-prompt -v repo=foo -v goal=perf
sp set-key sk-ant-... # (optional) enable AutoTag via Claude Haiku
```

## macOS — full app with hotkey

1. Open `Apps/SmartPromptingMac/*.swift` in a new Xcode project:
   - File → New → Project → macOS → App, product name `SmartPrompting`,
     bundle id `com.smartprompting.mac`, interface SwiftUI.
   - Delete Xcode's boilerplate and drag in the four files from
     `Apps/SmartPromptingMac/` + `Info.plist` + `SmartPromptingMac.entitlements`.
   - File → Add Package Dependencies → "Add Local…" → pick the repo root so
     the target links `SmartPromptingCore`.
   - Set Signing & Capabilities → Team = **None**, "Sign to Run Locally".
     Add the iCloud capability with container `iCloud.com.smartprompting.library`.
2. Build & Run (⌘R). The menu bar icon appears.
3. For a distributable DMG: `make mac` → drag
   `build/SmartPrompting.dmg` → Applications. First launch: **right-click →
   Open → Open** (one-time Gatekeeper bypass). Or:
   `xattr -dr com.apple.quarantine /Applications/SmartPrompting.app`.
4. `make install-launchd` registers a login-item so the hotkey survives
   reboots.

First time you press **⌥⌘P**, macOS asks for Accessibility permission — grant
it in System Settings → Privacy & Security → Accessibility.

## iPhone — install (two free paths)

### Path A · Xcode direct install (simplest)

1. On iPhone: Settings → Privacy & Security → **Developer Mode → On** (iOS 16+).
2. In Xcode: create a new iOS App project at `Apps/SmartPromptingiOS.xcodeproj`.
   - Product name `SmartPrompting`, bundle id `com.smartprompting.ios`.
   - Drag in the Swift files from `Apps/SmartPromptingiOS/`, add the
     `ShareExtension` target (share extension template), and link
     `SmartPromptingCore` as a local Swift package.
   - Signing & Capabilities → Team = your free personal team.
   - Add the iCloud capability with container
     `iCloud.com.smartprompting.library` — **it must exactly match the Mac
     container** for sync to work.
3. Connect iPhone, select it as the run destination, press ⌘R.
4. On iPhone: Settings → General → VPN & Device Management → trust your
   Apple ID once.

Provisioning profiles from a free Apple ID last **7 days**. To refresh:
`make refresh-ios` (plug in or use Wi-Fi debugging, no App Store upload).

### Path B · AltStore sideload (works without Xcode after first setup)

1. Install AltServer on your Mac, then AltStore on the iPhone via AltServer.
   See https://altstore.io for instructions (free).
2. `DEVELOPMENT_TEAM=<your-team> make ios` → produces
   `build/SmartPrompting.ipa`.
3. Drop the `.ipa` into iCloud Drive. On iPhone: AltStore → My Apps → ＋ →
   pick the `.ipa` → sign with Apple ID.
4. As long as AltServer runs on your Mac on the same Wi-Fi, AltStore
   auto-refreshes the 7-day signature in the background.

## How sync works

- The markdown files in `iCloud Drive/SmartPrompting/prompts/` are the source
  of truth. Each device's SQLite index at
  `~/Library/Application Support/SmartPrompting/index.sqlite` is a
  disposable cache rebuilt from the files.
- Concurrent edits on two devices produce iCloud conflict copies, which show
  up as sibling `.md` files — resolve by keeping the one you want.
- If iCloud is unavailable, prompts fall back to
  `~/Library/Application Support/SmartPrompting/prompts/` (Mac only).

## AutoTag (optional, free tier)

Set an Anthropic API key once and titles/tags are generated on save with
Claude Haiku (~$0.0001 per save):

```
sp set-key sk-ant-...
```

Without a key, the local fallback uses the first line of the prompt as the
title, leaves tags empty, and still extracts `{{placeholders}}` via regex —
the app is fully usable offline.

## Troubleshooting

- **`sp doctor` shows "hashing" backend**: you're on a platform without
  `NaturalLanguage` (e.g. Linux). Build & run on macOS to get real embeddings.
- **Hotkey does nothing**: grant Accessibility permission in System Settings.
- **iCloud path shows Application Support**: sign into iCloud and enable
  iCloud Drive in System Settings.
- **iOS app opens but list is empty**: confirm the iCloud container ID
  matches the Mac app in both entitlements files.
