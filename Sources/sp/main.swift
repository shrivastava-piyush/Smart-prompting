import ArgumentParser
import Darwin
import Foundation
import SmartPromptingCore

@main
struct SP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sp",
        abstract: "Smart Prompting CLI — save and recall long prompts.",
        subcommands: [Add.self, Find.self, Use.self, Assemble.self, Dag.self, List.self, Edit.self, Remove.self, History.self, Rollback.self, Stats.self, Doctor.self, SetKey.self],
        defaultSubcommand: Find.self
    )
}

// MARK: - sp add

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Save a new prompt. Reads from --file, stdin, or the clipboard."
    )

    @Option(name: [.short, .long], help: "Read prompt body from this file.")
    var file: String?

    @Option(name: [.customShort("t"), .long], help: "Override auto-generated title.")
    var title: String?

    @Flag(name: [.customShort("c"), .long], help: "Read prompt from clipboard (pbpaste).")
    var clipboard: Bool = false

    func run() async throws {
        let body = try readBody()
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("Empty prompt body.")
        }
        let sp = try SmartPrompting()
        let prompt = try await sp.create(from: body, titleHint: title)
        print("Saved: \(prompt.slug)  —  \(prompt.title)")
        if !prompt.tags.isEmpty {
            print("Tags: \(prompt.tags.joined(separator: ", "))")
        }
        if !prompt.placeholders.isEmpty {
            print("Placeholders: \(prompt.placeholders.map { "{{\($0)}}" }.joined(separator: " "))")
        }
    }

    private func readBody() throws -> String {
        if let file = file {
            return try String(contentsOfFile: file, encoding: .utf8)
        }
        if clipboard {
            return try runPbpaste()
        }
        // Stdin
        if isatty(fileno(stdin)) == 0 {
            var buf = ""
            while let line = readLine(strippingNewline: false) { buf += line }
            return buf
        }
        FileHandle.standardError.write(Data("Paste prompt, end with Ctrl-D:\n".utf8))
        var buf = ""
        while let line = readLine(strippingNewline: false) { buf += line }
        return buf
    }

    private func runPbpaste() throws -> String {
        let proc = Process()
        proc.launchPath = "/usr/bin/pbpaste"
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

// MARK: - sp find

struct Find: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search prompts. With no query, lists most-recent."
    )

    @Argument(parsing: .remaining) var query: [String] = []
    @Option(name: [.short, .long]) var limit: Int = 10
    @Flag(name: [.customShort("n"), .long], help: "Print top hit's body to stdout and exit (no picker).")
    var noInteractive: Bool = false

    func run() async throws {
        let sp = try SmartPrompting()
        let q = query.joined(separator: " ")
        let hits = try sp.search.query(q, limit: limit)
        if hits.isEmpty {
            FileHandle.standardError.write(Data("No matches.\n".utf8))
            return
        }
        if noInteractive, let top = hits.first {
            print(top.prompt.body)
            return
        }
        for (i, hit) in hits.enumerated() {
            let tags = hit.prompt.tags.isEmpty ? "" : "  [\(hit.prompt.tags.joined(separator: ", "))]"
            let score = String(format: "%.2f", hit.score)
            print("\(String(format: "%2d", i + 1)). \(hit.prompt.title)  (\(hit.prompt.slug))  score=\(score)\(tags)")
        }
        FileHandle.standardError.write(Data("Pick #: ".utf8))
        guard let choice = readLine(), let n = Int(choice), (1...hits.count).contains(n) else {
            return
        }
        let picked = hits[n - 1].prompt
        let rendered = try promptUse(sp: sp, prompt: picked)
        Clipboard.copy(rendered)
        print(rendered)
        FileHandle.standardError.write(Data("✓ copied to clipboard\n".utf8))
    }
}

// MARK: - sp use

struct Use: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a prompt by slug, filling any placeholders."
    )

    @Argument(help: "The slug (filename stem) of the prompt.") var slug: String
    @Option(name: [.customShort("v"), .long],
            parsing: .upToNextOption,
            help: "Placeholder values as key=value (repeatable).")
    var values: [String] = []

    @Flag(name: [.customShort("p"), .long], help: "Print to stdout only (do not copy to clipboard).")
    var printOnly: Bool = false

    func run() async throws {
        let sp = try SmartPrompting()
        guard let prompt = try sp.store.get(slug: slug) else {
            throw SmartPromptingError.promptNotFound(slug)
        }
        var map: [String: String] = [:]
        for kv in values {
            if let eq = kv.firstIndex(of: "=") {
                map[String(kv[..<eq])] = String(kv[kv.index(after: eq)...])
            }
        }
        for name in TemplateEngine.userPlaceholders(in: prompt.body) where map[name] == nil {
            FileHandle.standardError.write(Data("\(name): ".utf8))
            map[name] = readLine() ?? ""
        }
        let rendered = try TemplateEngine.render(prompt.body, with: map)
        try sp.store.recordUse(prompt)
        if !printOnly { Clipboard.copy(rendered) }
        print(rendered)
    }
}

// MARK: - sp assemble

struct Assemble: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assemble",
        abstract: "Assemble a composite prompt by resolving @{slug} fragment references."
    )

    @Argument(parsing: .remaining, help: "Query string or slug to assemble.")
    var query: [String] = []

    @Option(name: [.customShort("v"), .long],
            parsing: .upToNextOption,
            help: "Placeholder values as key=value (repeatable).")
    var values: [String] = []

    @Flag(name: [.customShort("s"), .long], help: "Use slug directly instead of searching.")
    var slug: Bool = false

    @Flag(name: [.customShort("p"), .long], help: "Print to stdout only (do not copy to clipboard).")
    var printOnly: Bool = false

    @Flag(name: [.long], help: "Show execution DAG before assembling.")
    var showDag: Bool = false

    func run() async throws {
        let sp = try SmartPrompting()
        let q = query.joined(separator: " ")
        guard !q.isEmpty else {
            throw ValidationError("Provide a slug or query to assemble.")
        }

        var map: [String: String] = [:]
        for kv in values {
            if let eq = kv.firstIndex(of: "=") {
                map[String(kv[..<eq])] = String(kv[kv.index(after: eq)...])
            }
        }

        // Resolve the root slug
        let rootSlug: String
        if slug {
            rootSlug = q
        } else {
            let hits = try sp.search.query(q, limit: 1)
            guard let top = hits.first else {
                throw SmartPromptingError.promptNotFound(q)
            }
            rootSlug = top.prompt.slug
        }

        // Collect missing placeholders interactively
        let placeholders = try sp.assembly.allPlaceholders(for: rootSlug)
        for (node, name) in placeholders where map[name] == nil {
            if TemplateEngine.systemVariableNames.contains(name.lowercased()) { continue }
            FileHandle.standardError.write(Data("[\(node)] \(name): ".utf8))
            map[name] = readLine() ?? ""
        }

        if showDag {
            let decomp = try sp.assembly.decompose(slug: rootSlug)
            printDAG(decomp)
            FileHandle.standardError.write(Data("\n--- Assembled output ---\n".utf8))
        }

        let result = try sp.assembly.assemble(slug: rootSlug, values: map)

        if !printOnly { Clipboard.copy(result.assembledText) }
        print(result.assembledText)

        if !printOnly {
            FileHandle.standardError.write(Data(
                "✓ assembled \(result.nodeCount) fragment\(result.nodeCount == 1 ? "" : "s") → clipboard\n".utf8
            ))
        }
    }

    private func printDAG(_ d: AssemblyEngine.Decomposition) {
        FileHandle.standardError.write(Data("DAG: \(d.nodes.count) node(s), root = \(d.rootSlug)\n".utf8))
        FileHandle.standardError.write(Data("Execution order: \(d.executionOrder.joined(separator: " → "))\n\n".utf8))
        for node in d.nodes.sorted(by: { d.executionOrder.firstIndex(of: $0.id) ?? 0 < d.executionOrder.firstIndex(of: $1.id) ?? 0 }) {
            let deps = node.dependencyCount > 0 ? " (requires \(node.dependencyCount) dep\(node.dependencyCount == 1 ? "" : "s"))" : ""
            let ph = node.hasPlaceholders ? " [has placeholders]" : ""
            FileHandle.standardError.write(Data("  [\(node.id)] \(node.title)\(deps)\(ph)\n".utf8))
        }
    }
}

// MARK: - sp dag

struct Dag: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dag",
        abstract: "Visualize the dependency graph for a composite prompt."
    )

    @Argument(help: "Slug of the root prompt.") var slug: String

    @Flag(name: [.long], help: "Output as JSON for programmatic use.")
    var json: Bool = false

    func run() async throws {
        let sp = try SmartPrompting()
        guard try sp.store.get(slug: slug) != nil else {
            throw SmartPromptingError.promptNotFound(slug)
        }

        let decomp = try sp.assembly.decompose(slug: slug)

        if json {
            printJSON(decomp)
        } else {
            printTree(decomp)
        }
    }

    private func printTree(_ d: AssemblyEngine.Decomposition) {
        let nodeMap = Dictionary(uniqueKeysWithValues: d.nodes.map { ($0.id, $0) })
        let childMap: [String: [String]] = {
            var m: [String: [String]] = [:]
            for e in d.edges { m[e.from, default: []].append(e.to) }
            return m
        }()

        print("Prompt DAG: \(d.rootSlug)")
        print("Nodes: \(d.nodes.count)  Edges: \(d.edges.count)")
        print("Execution: \(d.executionOrder.joined(separator: " → "))")
        print("")

        func walk(_ slug: String, prefix: String, isLast: Bool) {
            let connector = isLast ? "└── " : "├── "
            let node = nodeMap[slug]
            let title = node?.title ?? slug
            let extras: [String] = [
                node?.hasPlaceholders == true ? "{{…}}" : nil,
                (node?.dependencyCount ?? 0) > 0 ? "\(node!.dependencyCount) deps" : nil
            ].compactMap { $0 }
            let suffix = extras.isEmpty ? "" : "  (\(extras.joined(separator: ", ")))"
            print("\(prefix)\(connector)\(slug): \(title)\(suffix)")

            let children = childMap[slug] ?? []
            for (i, child) in children.enumerated() {
                let childPrefix = prefix + (isLast ? "    " : "│   ")
                walk(child, prefix: childPrefix, isLast: i == children.count - 1)
            }
        }

        // Find root (nodes with no incoming edges)
        let targets = Set(d.edges.map(\.to))
        let roots = d.nodes.filter { !targets.contains($0.id) }.map(\.id)
        for (i, root) in (roots.isEmpty ? [d.rootSlug] : roots).enumerated() {
            walk(root, prefix: "", isLast: i == roots.count - 1)
        }
    }

    private func printJSON(_ d: AssemblyEngine.Decomposition) {
        let obj: [String: Any] = [
            "root": d.rootSlug,
            "execution_order": d.executionOrder,
            "nodes": d.nodes.map { n -> [String: Any] in
                [
                    "id": n.id,
                    "title": n.title,
                    "body_preview": n.bodyPreview,
                    "dependency_count": n.dependencyCount,
                    "has_placeholders": n.hasPlaceholders
                ]
            },
            "edges": d.edges.map { ["from": $0.from, "to": $0.to] }
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]
        ), let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}

// MARK: - sp ls

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List prompts, most-recently-used first."
    )

    @Option(name: [.customShort("t"), .long]) var tag: String?

    func run() async throws {
        let sp = try SmartPrompting()
        let prompts = tag.map { try? sp.store.byTag($0) } ?? (try? sp.store.all())
        let list = prompts ?? []
        if list.isEmpty {
            FileHandle.standardError.write(Data("No prompts yet. Try: sp add\n".utf8))
            return
        }
        for p in list {
            let tags = p.tags.isEmpty ? "" : "  [\(p.tags.joined(separator: ", "))]"
            let uses = p.useCount == 0 ? "" : "  ×\(p.useCount)"
            print("\(p.slug.padding(toLength: 36, withPad: " ", startingAt: 0))  \(p.title)\(tags)\(uses)")
        }
    }
}

// MARK: - sp edit

struct Edit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a prompt's markdown file in $EDITOR."
    )

    @Argument var slug: String

    func run() async throws {
        let sp = try SmartPrompting()
        let url = sp.store.promptsDir.appendingPathComponent("\(slug).md")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SmartPromptingError.promptNotFound(slug)
        }
        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = [editor, url.path]
        try proc.run()
        proc.waitUntilExit()
        try sp.store.syncIndexFromDisk()
        print("Reindexed.")
    }
}

// MARK: - sp rm

struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Delete a prompt."
    )

    @Argument var slug: String
    @Flag(name: [.customShort("f"), .long]) var force: Bool = false

    func run() async throws {
        let sp = try SmartPrompting()
        guard try sp.store.get(slug: slug) != nil else {
            throw SmartPromptingError.promptNotFound(slug)
        }
        if !force {
            FileHandle.standardError.write(Data("Delete \(slug)? [y/N] ".utf8))
            guard (readLine() ?? "").lowercased().hasPrefix("y") else { return }
        }
        try sp.store.delete(slug: slug)
        print("Deleted \(slug).")
    }
}

// MARK: - sp doctor

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnose setup: iCloud status, storage path, embedding model, API key."
    )

    func run() async throws {
        let sp = try SmartPrompting()

        // iCloud status — the most important check
        let syncStatus = ICloudSync.status()
        switch syncStatus {
        case .syncing(let path):
            print("iCloud Drive:      ✓ signed in & syncing")
            print("                   Prompts saved on this Mac will appear on your iPhone.")
            print("Prompts directory: \(path)")
        case .local(let path, let reason):
            print("iCloud Drive:      ✗ NOT syncing")
            print("                   \(reason)")
            print("Prompts directory: \(path)  (local only — will NOT appear on other devices)")
        }

        print("Index DB:          \(sp.store.dbURL.path)")
        print("Embedding backend: \(Embeddings.shared.backend.rawValue) (\(Embeddings.shared.dimension)-dim)")
        let hasKey = KeychainConfig.anthropicAPIKey() != nil
        print("Anthropic API key: \(hasKey ? "✓ found (AutoTag via Claude Haiku)" : "✗ not set (local title/tag fallback)")")
        let all = try sp.store.all()
        print("Prompts indexed:   \(all.count)")

        if case .local = syncStatus {
            print("")
            print("To enable cross-device sync:")
            print("  1. Open System Settings → Apple ID → iCloud → iCloud Drive → turn ON")
            print("  2. Re-run `sp doctor` to confirm")
            print("  3. On iPhone: Settings → Apple ID → iCloud → iCloud Drive → ON (same Apple ID)")
        }
    }
}

// MARK: - sp set-key

struct SetKey: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-key",
        abstract: "Store an ANTHROPIC_API_KEY in the Keychain for AutoTag."
    )

    @Argument(help: "The API key. Omit to clear.") var key: String?

    func run() async throws {
        if let key = key, !key.isEmpty {
            if KeychainConfig.setAnthropicAPIKey(key) {
                print("Stored in Keychain.")
            } else {
                FileHandle.standardError.write(Data("Failed to write to Keychain.\n".utf8))
                throw ExitCode.failure
            }
        } else {
            _ = KeychainConfig.clearAnthropicAPIKey()
            print("Cleared.")
        }
    }
}

// MARK: - sp history

struct History: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show version history for a prompt."
    )

    @Argument(help: "The slug of the prompt.") var slug: String

    @Flag(name: [.customShort("b"), .long], help: "Print the body of a specific version.")
    var showBody: Bool = false

    @Option(name: [.customShort("v"), .long], help: "Version number to inspect.")
    var version: Int?

    func run() async throws {
        let sp = try SmartPrompting()
        guard try sp.store.get(slug: slug) != nil else {
            throw SmartPromptingError.promptNotFound(slug)
        }
        let versions = try sp.store.versions(of: slug)
        if versions.isEmpty {
            print("No version history for \(slug). History is created on each edit.")
            return
        }

        if let v = version {
            guard let entry = versions.first(where: { $0.version == v }) else {
                throw SmartPromptingError.promptNotFound("\(slug) version \(v)")
            }
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            print("Version \(entry.version)  —  \(df.string(from: entry.date))")
            if showBody, let p = entry.prompt {
                print("---")
                print(p.body)
            } else if let p = entry.prompt {
                print("Title: \(p.title)")
                print("Body:  \(String(p.body.prefix(120)))...")
                print("(use --show-body to see full text)")
            }
            return
        }

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        print("History for \(slug) (\(versions.count) version\(versions.count == 1 ? "" : "s")):\n")
        for entry in versions {
            let title = entry.prompt?.title ?? "—"
            let bodyPreview = entry.prompt.map { String($0.body.prefix(60)) } ?? ""
            print("  v\(String(format: "%3d", entry.version))  \(df.string(from: entry.date))  \(title)")
            if !bodyPreview.isEmpty {
                print("        \(bodyPreview)...")
            }
        }
        print("\nRollback: sp rollback \(slug) <version>")
    }
}

// MARK: - sp rollback

struct Rollback: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rollback",
        abstract: "Restore a prompt to a previous version."
    )

    @Argument(help: "The slug of the prompt.") var slug: String
    @Argument(help: "Version number to restore.") var version: Int

    @Flag(name: [.customShort("f"), .long]) var force: Bool = false

    func run() async throws {
        let sp = try SmartPrompting()
        guard try sp.store.get(slug: slug) != nil else {
            throw SmartPromptingError.promptNotFound(slug)
        }
        let versions = try sp.store.versions(of: slug)
        guard versions.contains(where: { $0.version == version }) else {
            throw SmartPromptingError.promptNotFound("\(slug) version \(version)")
        }
        if !force {
            FileHandle.standardError.write(Data("Rollback \(slug) to version \(version)? Current version will be saved to history. [y/N] ".utf8))
            guard (readLine() ?? "").lowercased().hasPrefix("y") else { return }
        }
        let restored = try sp.store.rollback(slug: slug, to: version)
        print("Restored \(slug) to version \(version).")
        print("Title: \(restored.title)")
    }
}

// MARK: - sp stats

struct Stats: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Show usage analytics for your prompt library."
    )

    @Option(name: [.short, .long], help: "Number of top items to show.")
    var top: Int = 10

    func run() async throws {
        let sp = try SmartPrompting()
        let s = try sp.store.stats(topN: top)

        print("=== Smart Prompting Stats ===\n")
        print("Total prompts:  \(s.totalPrompts)")
        print("Total uses:     \(s.totalUses)")
        print("Never used:     \(s.unusedCount)")

        if s.totalPrompts > 0 {
            let avgUses = Double(s.totalUses) / Double(s.totalPrompts)
            print("Avg uses/prompt: \(String(format: "%.1f", avgUses))")
        }

        if !s.topByUse.isEmpty {
            print("\n--- Most Used ---")
            for (i, item) in s.topByUse.enumerated() {
                let bar = String(repeating: "█", count: min(item.uses, 30))
                print("\(String(format: "%2d", i + 1)). \(item.prompt.slug.padding(toLength: 30, withPad: " ", startingAt: 0))  \(String(format: "%4d", item.uses))x  \(bar)")
            }
        }

        if !s.recentlyUsed.isEmpty {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            print("\n--- Recently Used ---")
            for item in s.recentlyUsed {
                print("  \(item.prompt.slug.padding(toLength: 30, withPad: " ", startingAt: 0))  \(df.string(from: item.lastUsed))")
            }
        }

        if !s.tagDistribution.isEmpty {
            print("\n--- Tag Distribution ---")
            for item in s.tagDistribution.prefix(20) {
                let bar = String(repeating: "▪", count: min(item.count, 30))
                print("  \(item.tag.padding(toLength: 20, withPad: " ", startingAt: 0))  \(String(format: "%3d", item.count))  \(bar)")
            }
        }
    }
}

// MARK: - helpers

func promptUse(sp: SmartPrompting, prompt: Prompt) throws -> String {
    var map: [String: String] = [:]
    for name in TemplateEngine.userPlaceholders(in: prompt.body) {
        FileHandle.standardError.write(Data("\(name): ".utf8))
        map[name] = readLine() ?? ""
    }
    let rendered = try TemplateEngine.render(prompt.body, with: map)
    try sp.store.recordUse(prompt)
    return rendered
}
