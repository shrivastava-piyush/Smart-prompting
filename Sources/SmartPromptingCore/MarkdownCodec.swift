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
        if let last = p.lastUsed {
            fm["last_used"] = iso.string(from: last)
        } else {
            fm["last_used"] = NSNull()
        }
        let yamlBody = try Yams.dump(object: fm)
        return "---\n\(yamlBody)---\n\(p.body)"
    }

    public static func decode(_ text: String, slug: String) throws -> Prompt {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Robust frontmatter detection
        let lines = text.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            // Find the second "---"
            var closerIndex = -1
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    closerIndex = i
                    break
                }
            }
            
            if closerIndex != -1 {
                let yamlLines = lines[1..<closerIndex]
                let bodyLines = lines[(closerIndex + 1)...]
                
                let yamlText = yamlLines.joined(separator: "\n")
                let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let fm = try? Yams.load(yaml: yamlText) as? [String: Any] {
                    let id = (fm["id"] as? String) ?? UUID().uuidString
                    let title = (fm["title"] as? String) ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
                    let tags = (fm["tags"] as? [String]) ?? []
                    let placeholders = (fm["placeholders"] as? [String]) ?? []
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
                        created: created,
                        updated: updated,
                        useCount: useCount,
                        lastUsed: lastUsed
                    )
                }
            }
        }
        
        // Fallback for plain markdown or failed YAML
        return Prompt(
            id: UUID().uuidString,
            slug: slug,
            title: slug.replacingOccurrences(of: "-", with: " ").capitalized,
            body: trimmed,
            tags: [],
            placeholders: TemplateEngine.placeholders(in: trimmed),
            created: Date(),
            updated: Date()
        )
    }
}
