import SwiftUI
import SmartPromptingCore

struct PromptListView: View {
    @ObservedObject var vm: LibraryViewModel
    @State private var selected: Prompt?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !vm.iCloudSyncing {
                        iCloudBanner
                    }

                    if vm.results.isEmpty {
                        emptyState
                    } else {
                        promptGrid
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $vm.query, prompt: "Search prompts...")
            .onChange(of: vm.query) { _, _ in vm.search() }
            .refreshable { vm.refresh() }
            .navigationTitle("Smart Prompting")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(item: $selected) { p in
                PromptDetailView(prompt: p) { values in
                    vm.copy(p, values: values)
                    selected = nil
                }
            }
            .sheet(isPresented: $showAdd) {
                AddPromptView { body in
                    Task {
                        await vm.add(body: body)
                        showAdd = false
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !vm.toast.isEmpty {
                    toastBanner
                }
            }
        }
    }

    // MARK: - iCloud banner

    private var iCloudBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "icloud.slash")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("iCloud Sync Unavailable")
                    .font(.subheadline.weight(.semibold))
                Text(vm.iCloudMessage.isEmpty
                     ? "Sign into iCloud with the same Apple ID as your Mac."
                     : vm.iCloudMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Fix")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Prompt grid

    private var promptGrid: some View {
        LazyVStack(spacing: 12) {
            ForEach(vm.results, id: \.prompt.id) { hit in
                PromptCard(prompt: hit.prompt, score: hit.score) {
                    selected = hit.prompt
                } onQuickCopy: {
                    vm.copy(hit.prompt)
                } onDelete: {
                    vm.delete(hit.prompt)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 80)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "text.bubble")
                .font(.system(size: 56))
                .foregroundStyle(.quaternary)
            Text("No Prompts Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Save your first prompt with the **+** button\nor use `sp add` in the terminal.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                showAdd = true
            } label: {
                Label("Add Prompt", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding()
    }

    // MARK: - Toast

    private var toastBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(vm.toast)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThickMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: vm.toast)
        .task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { vm.toast = "" }
        }
    }
}

// MARK: - Prompt card

struct PromptCard: View {
    let prompt: Prompt
    let score: Double
    let onTap: () -> Void
    let onQuickCopy: () -> Void
    let onDelete: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Header: title + copy button
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if prompt.useCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Used \(prompt.useCount)\(prompt.useCount == 1 ? " time" : " times")")
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Button(action: onQuickCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.body)
                            .foregroundStyle(.accentColor)
                            .padding(8)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Body preview
                Text(prompt.body.prefix(160))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                // Placeholders
                if !prompt.placeholders.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "curlybraces")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(prompt.placeholders.map { "{{\($0)}}" }.joined(separator: "  "))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }

                // Tags
                if !prompt.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(prompt.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundStyle(.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onQuickCopy() } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }
            Button { onTap() } label: {
                Label("View & Fill Placeholders", systemImage: "square.and.pencil")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Detail view

struct PromptDetailView: View {
    let prompt: Prompt
    let onCopy: ([String: String]) -> Void

    @State private var values: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title card
                    VStack(alignment: .leading, spacing: 8) {
                        Text(prompt.title)
                            .font(.title2.weight(.bold))
                        if !prompt.tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(prompt.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundStyle(.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        HStack(spacing: 16) {
                            Label("Used \(prompt.useCount)x", systemImage: "arrow.counterclockwise")
                            Label(prompt.slug, systemImage: "link")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Placeholders
                    if !prompt.placeholders.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Placeholders", systemImage: "curlybraces")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            ForEach(prompt.placeholders, id: \.self) { name in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name)
                                        .font(.caption.weight(.medium).monospaced())
                                        .foregroundStyle(.secondary)
                                    TextField("Enter \(name)...", text: Binding(
                                        get: { values[name] ?? "" },
                                        set: { values[name] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding(20)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // Body
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt Body")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(prompt.body)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onCopy(values)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }
}

// MARK: - Add prompt view

struct AddPromptView: View {
    let onSave: (String) -> Void
    @State private var body: String = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header hint
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("Paste or type your prompt. Use `{{name}}` for placeholders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGroupedBackground))

                TextEditor(text: $body)
                    .font(.system(.body, design: .monospaced))
                    .focused($focused)
                    .padding(12)
                    .scrollContentBackground(.hidden)

                // Character count
                HStack {
                    Spacer()
                    Text("\(body.count) characters")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("New Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(body)
                    } label: {
                        Text("Save")
                            .font(.subheadline.weight(.bold))
                    }
                    .disabled(body.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}
