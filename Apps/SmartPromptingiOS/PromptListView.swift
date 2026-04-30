import SwiftUI
import UniformTypeIdentifiers
import SmartPromptingCore

struct PromptListView: View {
    @ObservedObject var vm: LibraryViewModel
    @State private var selected: Prompt?
    @State private var showAdd = false
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
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
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .searchable(text: $vm.query, placement: .automatic, prompt: "Search")
            .onChange(of: vm.query) { _, _ in vm.search() }
            .refreshable { vm.refresh() }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Sync Status / Settings Menu
                    Menu {
                        Section("Sync Settings") {
                            Button { showFolderPicker = true } label: {
                                Label("Change Sync Folder", systemImage: "folder.badge.gearshape")
                            }
                            Button { vm.forceSync() } label: {
                                Label("Force Re-index", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button(role: .destructive) { vm.resetDirectory() } label: {
                                Label("Reset to Local Only", systemImage: "arrow.counterclockwise")
                            }
                        }
                        
                        Section("Status") {
                            Text(vm.iCloudSyncing ? "iCloud Sync Active" : "Local Storage Only")
                        }
                    } label: {
                        Image(systemName: vm.iCloudSyncing ? "icloud.fill" : "icloud")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(vm.iCloudSyncing ? Color.accentColor : Color.secondary)
                    }

                    // Add Prompt
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $selected) { p in
                PromptActionView(
                    prompt: p,
                    sp: vm.spInstance,
                    onDismiss: { selected = nil },
                    onCopy: { text in
                        Clipboard.copy(text)
                        try? vm.spInstance?.store.recordUse(p)
                        vm.toast = "Copied: \(p.title)"
                        vm.refresh()
                        selected = nil
                    }
                )
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
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        vm.selectDirectory(url)
                    }
                case .failure(let error):
                    vm.toast = error.localizedDescription
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 100)
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.quaternary)
            
            VStack(spacing: 8) {
                Text("No Prompts Found")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Add your first prompt or select an iCloud folder to sync an existing library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
            
            Button {
                showFolderPicker = true
            } label: {
                Text("Sync with iCloud Folder")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }

    private var toastBanner: some View {
        Text(vm.toast)
            .font(.footnote.bold())
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.primary))
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct PromptCard: View {
    let prompt: Prompt
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if !prompt.tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(prompt.tags.prefix(3), id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if !prompt.placeholders.isEmpty {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Text(prompt.body)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
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
                    VStack(alignment: .leading, spacing: 12) {
                        Text(prompt.title)
                            .font(.headline)
                        Text(prompt.body)
                            .font(.body)
                    }
                    .padding(.vertical, 8)
                }

                if !prompt.placeholders.isEmpty {
                    Section("Required Inputs") {
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
            .navigationTitle("Prompt Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
                Section("Title") {
                    TextField("Enter title...", text: $title)
                }
                
                Section("Body") {
                    TextEditor(text: $promptBody)
                        .frame(minHeight: 250)
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
