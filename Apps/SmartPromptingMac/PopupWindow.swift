import SwiftUI
import SmartPromptingCore

struct PopupWindow: View {
    @ObservedObject var vm: LibraryViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var placeholderValues: [String: String] = [:]
    @State private var showingPlaceholders = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if showingPlaceholders, let p = selectedPrompt, !p.placeholders.isEmpty {
                placeholderForm(for: p)
            } else {
                resultsList
            }
            footer
        }
        .frame(width: 660, height: 480)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: HotkeyController.popupActivated)) { _ in
            searchFocused = true
            showingPlaceholders = false
            vm.query = ""
            vm.refresh()
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.tertiary)
            TextField("Search prompts...", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light))
                .focused($searchFocused)
                .onChange(of: vm.query) { _, _ in vm.search() }
                .onSubmit { handleEnter() }
                .onKeyPress(.downArrow) { vm.selectNext(); return .handled }
                .onKeyPress(.upArrow) { vm.selectPrevious(); return .handled }
                .onKeyPress(.escape) { dismissWindow(id: "popup"); return .handled }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    vm.search()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(vm.results.enumerated()), id: \.element.prompt.id) { idx, hit in
                        ResultRow(
                            prompt: hit.prompt,
                            selected: idx == vm.selectedIndex
                        )
                        .id(idx)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            vm.selectedIndex = idx
                            handleEnter()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: vm.selectedIndex) { _, newIdx in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    // MARK: - Placeholder form

    private func placeholderForm(for p: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "curlybraces")
                    .foregroundStyle(.orange)
                Text("Fill placeholders for")
                    .font(.subheadline)
                Text(p.title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.bottom, 4)

            ForEach(p.placeholders, id: \.self) { name in
                HStack(spacing: 12) {
                    Text("{{\(name)}}")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(.orange)
                        .frame(width: 140, alignment: .trailing)
                    TextField("Value...", text: Binding(
                        get: { placeholderValues[name] ?? "" },
                        set: { placeholderValues[name] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showingPlaceholders = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Copy") {
                    copyRendered()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if !vm.status.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(vm.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Group {
                    keyHint("return", "copy")
                    keyHint("esc", "dismiss")
                    keyHint("arrows", "navigate")
                }
            }
            Spacer()
            if !ICloudSync.isSyncing {
                HStack(spacing: 4) {
                    Image(systemName: "icloud.slash")
                        .font(.caption2)
                    Text("Not syncing")
                }
                .font(.caption2)
                .foregroundStyle(.orange)
            }
            Text("\(vm.results.count) results")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func keyHint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(action)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

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
            vm.status = "Copied to clipboard"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismissWindow(id: "popup")
                vm.status = ""
            }
        }
    }

    private func copyRendered() {
        if vm.useSelected(values: placeholderValues) != nil {
            vm.status = "Copied to clipboard"
            showingPlaceholders = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismissWindow(id: "popup")
                vm.status = ""
            }
        }
    }
}

// MARK: - Result row

struct ResultRow: View {
    let prompt: Prompt
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.05))
                    .frame(width: 36, height: 36)
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? .white : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(selected ? .white : .primary)
                    .lineLimit(1)

                Text(prompt.body.prefix(100))
                    .font(.caption)
                    .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(2)

                if !prompt.tags.isEmpty || !prompt.placeholders.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(prompt.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(selected ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.1))
                                .foregroundStyle(selected ? .white : .accentColor)
                                .clipShape(Capsule())
                        }
                        if !prompt.placeholders.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "curlybraces")
                                Text("\(prompt.placeholders.count)")
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(selected ? .white.opacity(0.7) : .orange)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if prompt.useCount > 0 {
                Text("\(prompt.useCount)x")
                    .font(.caption2)
                    .foregroundStyle(selected ? .white.opacity(0.6) : .quaternary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(selected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 4)
    }
}
