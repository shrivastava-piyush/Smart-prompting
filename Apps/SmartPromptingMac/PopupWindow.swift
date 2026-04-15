import SwiftUI
import SmartPromptingCore

/// Spotlight-like search window.
struct PopupWindow: View {
    @ObservedObject var vm: LibraryViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var placeholderValues: [String: String] = [:]
    @State private var showingPlaceholders = false

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if showingPlaceholders, let p = selectedPrompt, !p.placeholders.isEmpty {
                placeholderForm(for: p)
            } else {
                resultsList
            }
            statusBar
        }
        .frame(width: 620, height: 440)
        .background(.ultraThinMaterial)
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: HotkeyController.popupActivated)) { _ in
            searchFocused = true
            showingPlaceholders = false
            vm.refresh()
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find a prompt…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($searchFocused)
                .onChange(of: vm.query) { _, _ in vm.search() }
                .onSubmit { handleEnter() }
                .onKeyPress(.downArrow) { vm.selectNext(); return .handled }
                .onKeyPress(.upArrow) { vm.selectPrevious(); return .handled }
                .onKeyPress(.escape) { dismissWindow(id: "popup"); return .handled }
        }
        .padding(12)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(vm.results.enumerated()), id: \.element.prompt.id) { idx, hit in
                    PromptRow(
                        prompt: hit.prompt,
                        score: hit.score,
                        selected: idx == vm.selectedIndex
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.selectedIndex = idx
                        handleEnter()
                    }
                }
            }
        }
    }

    private func placeholderForm(for p: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fill placeholders for “\(p.title)”").font(.headline)
            ForEach(p.placeholders, id: \.self) { name in
                HStack {
                    Text("\(name):").frame(width: 120, alignment: .trailing)
                    TextField("", text: Binding(
                        get: { placeholderValues[name] ?? "" },
                        set: { placeholderValues[name] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { showingPlaceholders = false }
                    .keyboardShortcut(.cancelAction)
                Button("Copy") { copyRendered() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(vm.status.isEmpty ? "↵ copy · ⌘↵ copy & paste · esc dismiss" : vm.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(vm.results.count) results").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var selectedPrompt: Prompt? {
        guard vm.selectedIndex < vm.results.count else { return nil }
        return vm.results[vm.selectedIndex].prompt
    }

    private func handleEnter() {
        guard let p = selectedPrompt else { return }
        if !p.placeholders.isEmpty {
            placeholderValues = [:]
            showingPlaceholders = true
            return
        }
        if vm.useSelected() != nil {
            vm.status = "✓ copied to clipboard"
            dismissWindow(id: "popup")
        }
    }

    private func copyRendered() {
        if vm.useSelected(values: placeholderValues) != nil {
            vm.status = "✓ copied to clipboard"
            showingPlaceholders = false
            dismissWindow(id: "popup")
        }
    }
}

struct PromptRow: View {
    let prompt: Prompt
    let score: Double
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(selected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title)
                    .fontWeight(.medium)
                    .foregroundStyle(selected ? .white : .primary)
                Text(prompt.body.prefix(120))
                    .font(.caption)
                    .foregroundStyle(selected ? .white.opacity(0.9) : .secondary)
                    .lineLimit(2)
                if !prompt.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(prompt.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(selected ? 0.5 : 0.2))
                                .foregroundStyle(selected ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor : Color.clear)
    }
}
