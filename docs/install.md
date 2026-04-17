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

## How sync works (important — read this first)

Smart Prompting does **not** have its own login or account system. Sync is
handled entirely by **iCloud Drive**, which is built into macOS and iOS.

### Setup (one-time per device)

| Device | What to do |
|---|---|
| **Mac** | System Settings → Apple ID → iCloud → iCloud Drive → **ON** |
| **iPhone** | Settings → [your name] → iCloud → iCloud Drive → **ON** |

Both devices must be signed into the **same Apple ID**. That's it — no tokens,
no passwords in the app.

### How to verify sync is working

```bash
sp doctor
```

You should see:

```
iCloud Drive:      ✓ signed in & syncing
                   Prompts saved on this Mac will appear on your iPhone.
```

If you see `✗ NOT syncing`, follow the instructions it prints.

On iPhone, the app shows an orange **"iCloud Drive Not Connected"** banner at
the top of the prompt list if sync isn't available, with a direct link to
Settings.

### What actually syncs

- The markdown files in `~/Library/Mobile Documents/.../SmartPrompting/prompts/`
  are the source of truth. iCloud Drive pushes new/changed files to all devices
  signed into the same Apple ID.
- Each device has its own disposable SQLite index at
  `~/Library/Application Support/SmartPrompting/index.sqlite` — rebuilt from
  the files on demand. Safe to delete.
- Concurrent edits on two devices produce iCloud conflict copies (sibling
  `.md` files). Resolve by keeping the one you want.
- If iCloud is unavailable, prompts fall back to
  `~/Library/Application Support/SmartPrompting/prompts/` (local only —
  won't sync).

## Custom keyboard (iOS)

Smart Prompting includes a **custom keyboard extension** that lets you search
and insert prompts directly from *any* text field on iPhone — ChatGPT, Claude,
Safari, Notes, etc.

### Enable it

1. After installing the app: Settings → General → Keyboard → Keyboards →
   **Add New Keyboard** → **Smart Prompting**.
2. Tap "Smart Prompting" in the list → toggle **Allow Full Access** ON.
   (Needed so the keyboard can read your prompt files from iCloud Drive.)
3. In any text field, tap the 🌐 globe key to switch to Smart Prompting.

### How it works

- A search bar at the top lets you find prompts by keyword or semantic match.
- Tap a result to **insert the full prompt text** at the cursor position.
- Tap the 🌐 globe button to switch back to the regular keyboard.
- If a prompt has `{{placeholders}}`, they're inserted as-is so you can
  fill them in manually.

## AutoTag (optional, free tier)

Set an Anthropic API key once and titles/tags are generated on save with
Claude Haiku (~$0.0001 per save):

```
sp set-key sk-ant-...
```

Without a key, the local fallback extracts a smart title from the prompt body
(strips filler words, title-cases the core action phrase), generates keyword
tags via frequency analysis, and extracts `{{placeholders}}` via regex — the
app is fully usable offline.

## Troubleshooting

- **`sp doctor` shows "✗ NOT syncing"**: sign into iCloud and enable iCloud
  Drive. On Mac: System Settings → Apple ID → iCloud → iCloud Drive. On
  iPhone: Settings → [your name] → iCloud → iCloud Drive.
- **iOS app shows "iCloud Drive Not Connected"**: same fix — sign in with
  the **same Apple ID** as your Mac.
- **iOS app opens but prompt list is empty**: (1) check that iCloud Drive
  is enabled on both devices with the same Apple ID; (2) wait ~60 seconds
  for iCloud to sync; (3) pull-to-refresh in the app.
- **`sp doctor` shows "hashing" backend**: you're on a platform without
  `NaturalLanguage` (e.g. Linux). Build & run on macOS to get real embeddings.
- **Hotkey does nothing**: grant Accessibility permission in System Settings →
  Privacy & Security → Accessibility.
- **Keyboard extension doesn't appear**: Settings → General → Keyboard →
  Keyboards → Add → Smart Prompting. Toggle "Allow Full Access".
