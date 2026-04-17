import SwiftUI
import SmartPromptingCore

struct PromptListView: View {
    @ObservedObject var vm: LibraryViewModel
    @State private var selected: Prompt?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if !vm.iCloudSyncing {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.icloud")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("iCloud Drive Not Connected")
                                    .font(.subheadline.weight(.semibold))
                                Text(vm.iCloudMessage.isEmpty
                                     ? "Sign into iCloud with the same Apple ID as your Mac to sync prompts across devices."
                                     : vm.iCloudMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .font(.caption.weight(.medium))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(vm.results, id: \.prompt.id) { hit in
                    Button { selected = hit.prompt } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hit.prompt.title).font(.body)
                            Text(hit.prompt.body.prefix(120))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if !hit.prompt.tags.isEmpty {
                                HStack {
                                    ForEach(hit.prompt.tags, id: \.self) { tag in
                                        Text(tag).font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { vm.delete(hit.prompt) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .searchable(text: $vm.query)
            .onChange(of: vm.query) { _, _ in vm.search() }
            .navigationTitle("Smart Prompting")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
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
                    Text(vm.toast)
                        .padding(8).padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding()
                        .transition(.opacity)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            vm.toast = ""
                        }
                }
            }
        }
    }
}

struct PromptDetailView: View {
    let prompt: Prompt
    let onCopy: ([String: String]) -> Void

    @State private var values: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { Text(prompt.title) }
                if !prompt.placeholders.isEmpty {
                    Section("Placeholders") {
                        ForEach(prompt.placeholders, id: \.self) { name in
                            TextField(name, text: Binding(
                                get: { values[name] ?? "" },
                                set: { values[name] = $0 }
                            ))
                        }
                    }
                }
                Section("Body") {
                    ScrollView { Text(prompt.body).font(.system(.caption, design: .monospaced)) }
                        .frame(maxHeight: 200)
                }
                if !prompt.tags.isEmpty {
                    Section("Tags") { Text(prompt.tags.joined(separator: ", ")) }
                }
            }
            .navigationTitle("Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { onCopy(values) }
                }
            }
        }
    }
}

struct AddPromptView: View {
    let onSave: (String) -> Void
    @State private var body: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $body)
                .font(.system(.body, design: .monospaced))
                .padding()
                .navigationTitle("New Prompt")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(body) }
                            .disabled(body.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
        }
    }
}
