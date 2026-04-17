import SwiftUI
import SmartPromptingCore

struct MenuBarScene: View {
    @ObservedObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Smart Prompting").font(.headline)
                Spacer()
                Button("Open") { openWindow(id: "popup") }
                    .buttonStyle(.borderless)
            }

            Divider()

            if !ICloudSync.isSyncing {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text("iCloud not connected")
                            .font(.caption.weight(.semibold))
                        Text("Prompts won't sync to iPhone. Sign into iCloud Drive in System Settings.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
            }

            if vm.allPrompts.isEmpty {
                Text("No prompts yet.\nUse `sp add` in the terminal, or drop a .md file into the prompts folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recent").font(.caption).foregroundStyle(.secondary)
                ForEach(vm.allPrompts.prefix(7)) { p in
                    Button(action: { copy(p) }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text(p.title).lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider()

            HStack {
                Button("Add from clipboard") { addFromClipboard() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vm.refresh() }
    }

    private func copy(_ p: Prompt) {
        Clipboard.copy(p.body)
        vm.status = "✓ \(p.title)"
    }

    private func addFromClipboard() {
        let body = NSPasteboard.general.string(forType: .string) ?? ""
        Task { await vm.addFromText(body) }
    }
}
