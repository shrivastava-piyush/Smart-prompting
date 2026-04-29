import Foundation
import GRDB

/// Markdown-file-backed store with a local SQLite index (FTS5 + embedding blobs).
///
/// The markdown files in iCloud Drive are the source of truth. The SQLite index
/// is rebuilt from them on demand — safe to delete at any time.
public final class PromptStore: @unchecked Sendable {
    public let promptsDir: URL
    public let dbURL: URL
    private let dbQueue: DatabaseQueue
    private let embeddings: Embeddings

    public init(
        promptsDir: URL? = nil,
        indexDir: URL? = nil,
        embeddings: Embeddings = .shared
    ) throws {
        self.promptsDir = try promptsDir ?? ICloudSync.promptsDirectory()
        let idx = try indexDir ?? ICloudSync.indexDirectory()
        self.dbURL = idx.appendingPathComponent("index.sqlite")
        self.embeddings = embeddings
        self.dbQueue = try DatabaseQueue(path: dbURL.path)
        try migrate()
        try syncIndexFromDisk()
    }

    // MARK: - Schema

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "prompts") { t in
                t.column("id", .text).primaryKey()
                t.column("slug", .text).notNull().unique()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("tags_json", .text).notNull().defaults(to: "[]")
                t.column("placeholders_json", .text).notNull().defaults(to: "[]")
                t.column("created", .datetime).notNull()
                t.column("updated", .datetime).notNull()
                t.column("use_count", .integer).notNull().defaults(to: 0)
                t.column("last_used", .datetime)
                t.column("embedding", .blob)
                t.column("file_mtime", .double).notNull().defaults(to: 0)
            }
            try db.create(virtualTable: "prompts_fts", using: FTS5()) { t in
                t.column("title")
                t.column("body")
                t.column("tags")
                t.column("slug")
                t.tokenizer = .porter(wrapping: .unicode61(diacritics: .remove))
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - CRUD on disk + index

    /// Create a new prompt, write markdown, update index. Returns final Prompt.
    @discardableResult
    public func add(_ prompt: Prompt) throws -> Prompt {
        var p = prompt
        if p.placeholders.isEmpty {
            p.placeholders = TemplateEngine.placeholders(in: p.body)
        }
        let baseSlug = p.slug.isEmpty ? Slug.make(from: p.title) : p.slug
        p.slug = Slug.uniqueSlug(base: baseSlug, in: promptsDir)
        p.updated = Date()

        let url = fileURL(for: p.slug)
        let text = try MarkdownCodec.encode(p)
        try text.write(to: url, atomically: true, encoding: .utf8)

        try upsertIndex(p, fileMTime: mtime(of: url))
        return p
    }

    /// Overwrite an existing prompt. The slug is preserved.
    /// Automatically saves the previous version before overwriting.
    @discardableResult
    public func update(_ prompt: Prompt) throws -> Prompt {
        var p = prompt
        p.placeholders = TemplateEngine.placeholders(in: p.body)
        p.updated = Date()
        let url = fileURL(for: p.slug)

        // Save previous version before overwriting
        if FileManager.default.fileExists(atPath: url.path) {
            try saveVersion(slug: p.slug)
        }

        let text = try MarkdownCodec.encode(p)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try upsertIndex(p, fileMTime: mtime(of: url))
        return p
    }

    public func delete(slug: String) throws {
        let url = fileURL(for: slug)
        try? FileManager.default.removeItem(at: url)
        _ = try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM prompts WHERE slug = ?", arguments: [slug])
            try db.execute(sql: "DELETE FROM prompts_fts WHERE slug = ?", arguments: [slug])
        }
    }

    public func get(slug: String) throws -> Prompt? {
        try dbQueue.read { db in
            try self.row(db, slug: slug)
        }
    }

    public func get(id: String) throws -> Prompt? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM prompts WHERE id = ?",
                arguments: [id]
            ) else { return nil }
            return Self.promptFromRow(row)
        }
    }

    public func all() throws -> [Prompt] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM prompts ORDER BY COALESCE(last_used, updated) DESC"
            )
            return rows.map(Self.promptFromRow)
        }
    }

    public func byTag(_ tag: String) throws -> [Prompt] {
        try all().filter { $0.tags.contains(tag) }
    }

    public func recordUse(_ prompt: Prompt) throws {
        var p = prompt
        p.useCount += 1
        p.lastUsed = Date()
        _ = try update(p)
    }

    // MARK: - Index rebuild from disk

    /// Walk the prompts directory, upsert new/changed files, remove stale rows.
    public func syncIndexFromDisk() throws {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: promptsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        var slugsOnDisk = Set<String>()
        for file in files where file.pathExtension == "md" {
            let slug = file.deletingPathExtension().lastPathComponent
            slugsOnDisk.insert(slug)
            let mtime = self.mtime(of: file)
            let indexed: Double = (try? dbQueue.read { db in
                try Double.fetchOne(
                    db,
                    sql: "SELECT file_mtime FROM prompts WHERE slug = ?",
                    arguments: [slug]
                )
            }) ?? 0
            if mtime > indexed {
                if let text = try? String(contentsOf: file, encoding: .utf8),
                   let p = try? MarkdownCodec.decode(text, slug: slug) {
                    try upsertIndex(p, fileMTime: mtime)
                }
            }
        }

        // Remove index rows for files that no longer exist.
        let allIndexed: [String] = (try? dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT slug FROM prompts")
        }) ?? []
        for slug in allIndexed where !slugsOnDisk.contains(slug) {
            _ = try? dbQueue.write { db in
                try db.execute(sql: "DELETE FROM prompts WHERE slug = ?", arguments: [slug])
                try db.execute(sql: "DELETE FROM prompts_fts WHERE slug = ?", arguments: [slug])
            }
        }
    }

    // MARK: - FTS + embedding access (used by Search)

    internal func ftsSearch(_ query: String, limit: Int = 50) throws -> [(slug: String, rank: Double)] {
        let escaped = Self.escapeFTS(query)
        guard !escaped.isEmpty else { return [] }
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT slug, bm25(prompts_fts) AS rank
                    FROM prompts_fts
                    WHERE prompts_fts MATCH ?
                    ORDER BY rank
                    LIMIT ?
                """,
                arguments: [escaped, limit]
            )
            return rows.map { row in
                (slug: row["slug"] as String, rank: row["rank"] as Double)
            }
        }
    }

    internal func allEmbeddings() throws -> [(slug: String, vector: [Float])] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT slug, embedding FROM prompts WHERE embedding IS NOT NULL"
            )
            return rows.map { row in
                let slug: String = row["slug"]
                let data: Data = row["embedding"] ?? Data()
                return (slug: slug, vector: Embeddings.unpack(data))
            }
        }
    }

    // MARK: - Version history

    private var versionsDir: URL {
        promptsDir.appendingPathComponent(".versions")
    }

    private func versionDir(for slug: String) -> URL {
        versionsDir.appendingPathComponent(slug)
    }

    private func saveVersion(slug: String) throws {
        let url = fileURL(for: slug)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let dir = versionDir(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let next = nextVersionNumber(for: slug)
        let dest = dir.appendingPathComponent("v\(next).md")
        try FileManager.default.copyItem(at: url, to: dest)
    }

    private func nextVersionNumber(for slug: String) -> Int {
        let dir = versionDir(for: slug)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return 1
        }
        let nums = files.compactMap { name -> Int? in
            guard name.hasPrefix("v"), name.hasSuffix(".md") else { return nil }
            let stem = name.dropFirst(1).dropLast(3)
            return Int(stem)
        }
        return (nums.max() ?? 0) + 1
    }

    /// List all saved versions for a slug, newest first.
    public func versions(of slug: String) throws -> [PromptVersion] {
        let dir = versionDir(for: slug)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        return files.compactMap { url -> PromptVersion? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("v"), let num = Int(name.dropFirst(1)) else { return nil }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let date = (attrs?[.modificationDate] as? Date) ?? Date()
            let text = try? String(contentsOf: url, encoding: .utf8)
            let prompt = text.flatMap { try? MarkdownCodec.decode($0, slug: slug) }
            return PromptVersion(version: num, date: date, prompt: prompt)
        }
        .sorted { $0.version > $1.version }
    }

    /// Restore a specific version, making it the current prompt.
    @discardableResult
    public func rollback(slug: String, to version: Int) throws -> Prompt {
        let dir = versionDir(for: slug)
        let src = dir.appendingPathComponent("v\(version).md")
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw SmartPromptingError.promptNotFound("\(slug) version \(version)")
        }
        let text = try String(contentsOf: src, encoding: .utf8)
        guard var prompt = try? MarkdownCodec.decode(text, slug: slug) else {
            throw SmartPromptingError.invalidMarkdown("cannot decode version \(version)")
        }
        prompt.updated = Date()
        let url = fileURL(for: slug)

        // Save current as a new version before rollback
        if FileManager.default.fileExists(atPath: url.path) {
            try saveVersion(slug: slug)
        }

        let encoded = try MarkdownCodec.encode(prompt)
        try encoded.write(to: url, atomically: true, encoding: .utf8)
        try upsertIndex(prompt, fileMTime: mtime(of: url))
        return prompt
    }

    // MARK: - Usage analytics

    public struct UsageStats {
        public let totalPrompts: Int
        public let totalUses: Int
        public let topByUse: [(prompt: Prompt, uses: Int)]
        public let recentlyUsed: [(prompt: Prompt, lastUsed: Date)]
        public let tagDistribution: [(tag: String, count: Int)]
        public let unusedCount: Int
    }

    public func stats(topN: Int = 10) throws -> UsageStats {
        let all = try self.all()
        let totalPrompts = all.count
        let totalUses = all.reduce(0) { $0 + $1.useCount }

        let topByUse = all
            .filter { $0.useCount > 0 }
            .sorted { $0.useCount > $1.useCount }
            .prefix(topN)
            .map { (prompt: $0, uses: $0.useCount) }

        let recentlyUsed = all
            .compactMap { p -> (prompt: Prompt, lastUsed: Date)? in
                guard let last = p.lastUsed else { return nil }
                return (prompt: p, lastUsed: last)
            }
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(topN)
            .map { $0 }

        var tagCounts: [String: Int] = [:]
        for p in all {
            for tag in p.tags { tagCounts[tag, default: 0] += 1 }
        }
        let tagDistribution = tagCounts
            .sorted { $0.value > $1.value }
            .map { (tag: $0.key, count: $0.value) }

        let unusedCount = all.filter { $0.useCount == 0 }.count

        return UsageStats(
            totalPrompts: totalPrompts,
            totalUses: totalUses,
            topByUse: Array(topByUse),
            recentlyUsed: Array(recentlyUsed),
            tagDistribution: tagDistribution,
            unusedCount: unusedCount
        )
    }

    // MARK: - Private helpers

    private func fileURL(for slug: String) -> URL {
        promptsDir.appendingPathComponent("\(slug).md")
    }

    private func mtime(of url: URL) -> Double {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let date = attrs?[.modificationDate] as? Date {
            return date.timeIntervalSince1970
        }
        return 0
    }

    private func upsertIndex(_ p: Prompt, fileMTime: Double) throws {
        let vec = embeddings.embed("\(p.title)\n\(p.tags.joined(separator: " "))\n\(p.body)")
        let blob = Embeddings.pack(vec)
        let tagsJSON = Self.toJSON(p.tags)
        let placeholdersJSON = Self.toJSON(p.placeholders)

        _ = try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO prompts (
                        id, slug, title, body, tags_json, placeholders_json,
                        created, updated, use_count, last_used, embedding, file_mtime
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(slug) DO UPDATE SET
                        id = excluded.id,
                        title = excluded.title,
                        body = excluded.body,
                        tags_json = excluded.tags_json,
                        placeholders_json = excluded.placeholders_json,
                        created = excluded.created,
                        updated = excluded.updated,
                        use_count = excluded.use_count,
                        last_used = excluded.last_used,
                        embedding = excluded.embedding,
                        file_mtime = excluded.file_mtime
                """,
                arguments: [
                    p.id, p.slug, p.title, p.body,
                    tagsJSON, placeholdersJSON,
                    p.created, p.updated, p.useCount, p.lastUsed,
                    blob, fileMTime
                ]
            )
            try db.execute(
                sql: "DELETE FROM prompts_fts WHERE slug = ?",
                arguments: [p.slug]
            )
            try db.execute(
                sql: """
                    INSERT INTO prompts_fts (slug, title, body, tags)
                    VALUES (?, ?, ?, ?)
                """,
                arguments: [p.slug, p.title, p.body, p.tags.joined(separator: " ")]
            )
        }
    }

    private func row(_ db: Database, slug: String) throws -> Prompt? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM prompts WHERE slug = ?", arguments: [slug]
        ) else { return nil }
        return Self.promptFromRow(row)
    }

    private static func promptFromRow(_ row: Row) -> Prompt {
        let tagsJSON: String = row["tags_json"] ?? "[]"
        let placeholdersJSON: String = row["placeholders_json"] ?? "[]"
        return Prompt(
            id: row["id"],
            slug: row["slug"],
            title: row["title"],
            body: row["body"],
            tags: (try? fromJSON(tagsJSON)) ?? [],
            placeholders: (try? fromJSON(placeholdersJSON)) ?? [],
            created: row["created"],
            updated: row["updated"],
            useCount: row["use_count"],
            lastUsed: row["last_used"]
        )
    }

    private static func toJSON(_ arr: [String]) -> String {
        (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
    }

    private static func fromJSON(_ s: String) throws -> [String] {
        guard let data = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Escape a user query for FTS5 MATCH (wrap each token as a prefix phrase).
    private static func escapeFTS(_ q: String) -> String {
        let cleaned = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { "\"\(String($0))\"*" }
            .joined(separator: " OR ")
        return cleaned
    }
}
