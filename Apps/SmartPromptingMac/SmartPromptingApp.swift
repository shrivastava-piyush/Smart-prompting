import SwiftUI
import SmartPromptingCore

@main
struct SmartPromptingApp: App {
    @StateObject private var vm = LibraryViewModel()
    @StateObject private var hotkey = HotkeyController()

    var body: some Scene {
        MenuBarExtra("Smart Prompting", systemImage: "text.bubble") {
            MenuBarScene(vm: vm)
        }
        .menuBarExtraStyle(.window)

        Window("Smart Prompting", id: "popup") {
            PopupWindow(vm: vm)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(hotkey: hotkey)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var hotkey: HotkeyController

    var body: some View {
        Form {
            Section("Global shortcut") {
                Text("Default: ⌥⌘P")
                Text("Customize by editing HotkeyController.swift")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section("API key") {
                APIKeyField()
            }
        }
        .padding()
        .frame(width: 420, height: 260)
    }
}

struct APIKeyField: View {
    @State private var key: String = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Anthropic API key (optional, enables AutoTag on save)")
                .font(.caption)
            SecureField("sk-ant-...", text: $key)
            HStack {
                Button("Save") {
                    if KeychainConfig.setAnthropicAPIKey(key) { saved = true }
                }
                .disabled(key.isEmpty)
                if saved { Text("Stored in Keychain").font(.caption).foregroundStyle(.green) }
            }
        }
    }
}
