import SwiftUI
import SmartPromptingCore

struct PromptListView: View {
    @ObservedObject var vm: LibraryViewModel
    @State private var selected: Prompt?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !vm.iCloudSyncing {
                        iCloudBanner
                    }

                    if vm.results.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.results, id: \.prompt.id) { hit in
                            PromptCard(prompt: hit.prompt) {
                                selected = hit.prompt
                            }
                            .contextMenu {
                                Button { vm.copy(hit.prompt) } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) { vm.delete(hit.prompt) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $vm.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Library")
            .onChange(of: vm.query) { _, _ in vm.search() }
            .refreshable { vm.refresh() }
            .navigationTitle("Prompts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title2)
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
                AddPromptView { title, body in
                    Task {
                        await vm.add(title: title, body: body)
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

    private var iCloudBanner: some View {
        HStack {
            Label("iCloud Sync Off", systemImage: "icloud.slash")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.orange.opacity(0.5))
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 80)
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.quaternary)
            Text("No Prompts Found")
                .font(.headline)
            Text("Your library is empty or matches nothing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var toastBanner: some View {
        Text(vm.toast)
            .font(.footnote.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.primary))
            .padding(.bottom, 20)
    }
}

struct PromptCard: View {
    let prompt: Prompt
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Category/Title Header
                HStack {
                    Text(prompt.title.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    
                    Spacer()
                    
                    if !prompt.placeholders.isEmpty {
                        Image(systemName: "variable")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }

                // Main Content
                Text(prompt.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Footer
                HStack(spacing: 8) {
                    if !prompt.tags.isEmpty {
                        ForEach(prompt.tags.prefix(2), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    
                    Spacer()
                    
                    Label("\(prompt.useCount)", systemImage: "bolt.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
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
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(prompt.title.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(prompt.body)
                            .font(.body)
                    }
                    .padding(.vertical, 8)
                }

                if !prompt.placeholders.isEmpty {
                    Section("Inputs") {
                        ForEach(prompt.placeholders, id: \.self) { name in
                            TextField(name, text: Binding(
                                get: { values[name] ?? "" },
                                set: { values[name] = $0 }
                            ))
                        }
                    }
                }

                Section {
                    Button(action: { onCopy(values) }) {
                        Text("Copy to Clipboard")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .disabled(prompt.placeholders.contains { values[$0]?.isEmpty ?? true })
                    .listRowBackground(Color.accentColor)
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("Use Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AddPromptView: View {
    let onSave: (String, String) -> Void
    @State private var title: String = ""
    @State private var promptBody: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Identifier (e.g. Code Review)", text: $title)
                    .font(.headline)
                
                ZStack(alignment: .topLeading) {
                    if promptBody.isEmpty {
                        Text("Paste your prompt content here...")
                            .foregroundStyle(.placeholder)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $promptBody)
                        .frame(minHeight: 300)
                }
            }
            .navigationTitle("New Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(title, promptBody) }
                        .disabled(title.isEmpty || promptBody.isEmpty)
                        .bold()
                }
            }
        }
    }
}
