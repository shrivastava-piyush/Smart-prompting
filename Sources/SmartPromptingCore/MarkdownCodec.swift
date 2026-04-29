import Foundation
import Yams

/// Serializes/deserializes a Prompt to a single Markdown file with YAML frontmatter.
///
/// Layout:
///
/// ```
/// ---
/// id: <uuid>
/// title: Something
/// tags: [a, b]
/// placeholders: [name]
/// created: 2026-01-01T00:00:00Z
/// updated: 2026-01-01T00:00:00Z
/// use_count: 0
/// last_used: null
/// ---
/// <body text>
/// ```
public enum MarkdownCodec {
    private static let frontmatterDelimiter = "---\n"

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func encode(_ p: Prompt) throws -> String {
        var fm: [String: Any] = [
            "id": p.id,
            "title": p.title,
            "tags": p.tags,
            "placeholders": p.placeholders,
            "created": iso.string(from: p.created),
            "updated": iso.string(from: p.updated),
            "use_count": p.useCount
        ]
        if !p.requires.isEmpty {
            fm["requires"] = p.requires
        }
        if let last = p.lastUsed {
            fm["last_used"] = iso.string(from: last)
        } else {
            fm["last_used"] = NSNull()
        }
        let yamlBody = try Yams.dump(object: fm)
        return "---\n\(yamlBody)---\n\(p.body)"
    }

    public static func decode(_ text: String, slug: String) throws -> Prompt {
        guard text.hasPrefix("---\n") else {
            throw SmartPromptingError.invalidMarkdown("missing frontmatter opener")
        }
        let afterOpen = text.dropFirst(4) // drop "---\n"
        guard let closeRange = afterOpen.range(of: "\n---\n") else {
            throw SmartPromptingError.invalidMarkdown("missing frontmatter closer")
        }
        let yamlText = String(afterOpen[..<closeRange.lowerBound])
        let bodyStart = afterOpen.index(closeRange.upperBound, offsetBy: 0)
        let body = String(afterOpen[bodyStart...])

        guard let fm = try Yams.load(yaml: yamlText) as? [String: Any] else {
            throw SmartPromptingError.invalidMarkdown("frontmatter not a dictionary")
        }

        let id = (fm["id"] as? String) ?? UUID().uuidString
        let title = (fm["title"] as? String) ?? slug
        let tags = (fm["tags"] as? [String]) ?? []
        let placeholders = (fm["placeholders"] as? [String]) ?? []
        let requires = (fm["requires"] as? [String]) ?? []
        let created = (fm["created"] as? String).flatMap { iso.date(from: $0) } ?? Date()
        let updated = (fm["updated"] as? String).flatMap { iso.date(from: $0) } ?? created
        let useCount = (fm["use_count"] as? Int) ?? 0
        let lastUsed: Date? = {
            if let s = fm["last_used"] as? String { return iso.date(from: s) }
            return nil
        }()

        return Prompt(
            id: id,
            slug: slug,
            title: title,
            body: body,
            tags: tags,
            placeholders: placeholders,
            requires: requires,
            created: created,
            updated: updated,
            useCount: useCount,
            lastUsed: lastUsed
        )
    }
}
