import ArgumentParser
import Darwin
import Foundation
import SmartPromptingCore

@main
struct SP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sp",
        abstract: "Smart Prompting CLI — save and recall long prompts.",
        subcommands: [Add.self, Find.self, Use.self, List.self, Edit.self, Remove.self, Doctor.self, SetKey.self],
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
        for name in prompt.placeholders where map[name] == nil {
            FileHandle.standardError.write(Data("\(name): ".utf8))
            map[name] = readLine() ?? ""
        }
        let rendered = try TemplateEngine.render(prompt.body, with: map)
        try sp.store.recordUse(prompt)
        if !printOnly { Clipboard.copy(rendered) }
        print(rendered)
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
        abstract: "Diagnose setup: storage path, embedding model, API key presence."
    )

    func run() async throws {
        let sp = try SmartPrompting()
        print("Prompts directory: \(sp.store.promptsDir.path)")
        print("Index DB:          \(sp.store.dbURL.path)")
        print("Embedding backend: \(Embeddings.shared.backend.rawValue) (\(Embeddings.shared.dimension)d)")
        let hasKey = KeychainConfig.anthropicAPIKey() != nil
        print("Anthropic API key: \(hasKey ? "found (AutoTag enabled)" : "not set (local fallback)")")
        let all = try sp.store.all()
        print("Prompts indexed:   \(all.count)")
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

// MARK: - helpers

func promptUse(sp: SmartPrompting, prompt: Prompt) throws -> String {
    var map: [String: String] = [:]
    for name in prompt.placeholders {
        FileHandle.standardError.write(Data("\(name): ".utf8))
        map[name] = readLine() ?? ""
    }
    let rendered = try TemplateEngine.render(prompt.body, with: map)
    try sp.store.recordUse(prompt)
    return rendered
}
