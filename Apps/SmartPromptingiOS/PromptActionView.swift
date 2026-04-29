import SwiftUI
import SmartPromptingCore

/// Mode picker + execution view shown when a user taps a prompt.
/// Offers: Direct Copy, Assemble (resolve @{ref}), Task Breakdown (DAG), Reprompt.
struct PromptActionView: View {
    let prompt: Prompt
    let sp: SmartPrompting?
    let onDismiss: () -> Void
    let onCopy: (String) -> Void

    @State private var mode: AssemblyEngine.Mode = .direct
    @State private var values: [String: String] = [:]
    @State private var assembledText: String = ""
    @State private var decomposition: AssemblyEngine.Decomposition?
    @State private var errorMessage: String?
    @State private var repromptBody: String = ""

    @Environment(\.dismiss) private var dismiss

    private var hasRefs: Bool {
        !GraphExecutor.references(in: prompt.body).isEmpty || !prompt.requires.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    promptHeader
                    modePicker
                    modeContent
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Use Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        executeAction()
                    } label: {
                        Label(mode == .decompose ? "View DAG" : "Copy",
                              systemImage: mode == .decompose ? "eye" : "doc.on.doc.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .onAppear {
                repromptBody = prompt.body
                mode = hasRefs ? .assemble : .direct
            }
        }
    }

    // MARK: - Header

    private var promptHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.title)
                .font(.title3.weight(.bold))
            HStack(spacing: 12) {
                Label(prompt.slug, systemImage: "link")
                if hasRefs {
                    Label("\(GraphExecutor.references(in: prompt.body).count + prompt.requires.count) refs",
                          systemImage: "arrow.triangle.branch")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !prompt.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(prompt.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ModeCard(
                    icon: "doc.on.doc", title: "Direct Copy",
                    subtitle: "Copy as-is with placeholders filled",
                    selected: mode == .direct
                ) { mode = .direct }

                ModeCard(
                    icon: "puzzlepiece.extension", title: "Assemble",
                    subtitle: "Resolve @{ref} fragments into one prompt",
                    selected: mode == .assemble,
                    disabled: !hasRefs
                ) { mode = .assemble }

                ModeCard(
                    icon: "arrow.triangle.branch", title: "Task Breakdown",
                    subtitle: "View dependency DAG before executing",
                    selected: mode == .decompose,
                    disabled: !hasRefs
                ) { mode = .decompose }

                ModeCard(
                    icon: "pencil.and.outline", title: "Reprompt",
                    subtitle: "Edit body, then copy the modified version",
                    selected: mode == .reprompt
                ) { mode = .reprompt }
            }
        }
    }

    // MARK: - Mode content

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .direct, .assemble:
            placeholderForm
        case .decompose:
            dagView
        case .reprompt:
            repromptEditor
        }

        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .padding(12)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        if !assembledText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Result", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Text(assembledText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Placeholder form

    private var placeholderForm: some View {
        let userPH = TemplateEngine.userPlaceholders(in: prompt.body)
        return Group {
            if !userPH.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Placeholders", systemImage: "curlybraces")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(userPH, id: \.self) { name in
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
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - DAG view

    private var dagView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let d = decomposition {
                Label("Dependency Graph", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)

                Text("Execution: \(d.executionOrder.joined(separator: " → "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                ForEach(Array(d.executionOrder.enumerated()), id: \.offset) { i, slug in
                    if let node = d.nodes.first(where: { $0.id == slug }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(slug == d.rootSlug
                                          ? Color.accentColor.opacity(0.2)
                                          : Color.secondary.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                Text("\(i + 1)")
                                    .font(.caption.weight(.bold).monospaced())
                                    .foregroundStyle(slug == d.rootSlug ? .accentColor : .secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(node.title)
                                        .font(.subheadline.weight(.medium))
                                    if slug == d.rootSlug {
                                        Text("ROOT")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor)
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(node.bodyPreview)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    if node.dependencyCount > 0 {
                                        Label("\(node.dependencyCount) deps", systemImage: "link")
                                    }
                                    if node.hasPlaceholders {
                                        Label("{{…}}", systemImage: "curlybraces")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                Button {
                    loadDAG()
                } label: {
                    Label("Load DAG", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { loadDAG() }
    }

    // MARK: - Reprompt editor

    private var repromptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Edit Prompt", systemImage: "pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            TextEditor(text: $repromptBody)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Text("\(repromptBody.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Actions

    private func executeAction() {
        errorMessage = nil
        assembledText = ""

        do {
            switch mode {
            case .direct:
                let rendered = try TemplateEngine.render(prompt.body, with: values)
                assembledText = rendered
                onCopy(rendered)

            case .assemble:
                guard let sp = sp else { return }
                let result = try sp.assembly.assemble(slug: prompt.slug, values: values)
                assembledText = result.assembledText
                onCopy(result.assembledText)

            case .decompose:
                loadDAG()
                return

            case .reprompt:
                let rendered = try TemplateEngine.render(repromptBody, with: values)
                assembledText = rendered
                onCopy(rendered)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDAG() {
        guard let sp = sp else { return }
        do {
            decomposition = try sp.assembly.decompose(slug: prompt.slug)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Mode card

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: disabled ? {} : action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selected ? .accentColor : disabled ? .quaternary : .secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(disabled ? .quaternary : .primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(disabled ? .quaternary : .tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(selected
                        ? Color.accentColor.opacity(0.1)
                        : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.5 : 1)
    }
}
