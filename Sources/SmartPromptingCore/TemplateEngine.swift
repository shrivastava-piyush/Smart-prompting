import Foundation

/// Parses and renders {{placeholder}} templates.
/// Placeholder names match `[A-Za-z_][A-Za-z0-9_-]*`.
public enum TemplateEngine {
    private static let pattern = #"\{\{\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}"#

    /// Return all unique placeholder names in the given body, in first-seen order.
    public static func placeholders(in body: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var seen = Set<String>()
        var ordered: [String] = []
        regex.enumerateMatches(in: body, range: range) { match, _, _ in
            guard let match = match,
                  match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: body) else { return }
            let name = String(body[r])
            if seen.insert(name).inserted {
                ordered.append(name)
            }
        }
        return ordered
    }

    /// Render the body by substituting placeholder names with provided values.
    /// Throws `missingPlaceholder` if any placeholder has no value.
    public static func render(_ body: String, with values: [String: String]) throws -> String {
        let names = placeholders(in: body)
        for name in names where values[name] == nil {
            throw SmartPromptingError.missingPlaceholder(name)
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let ns = body as NSString
        var result = ""
        var cursor = 0
        regex.enumerateMatches(in: body, range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let whole = match.range(at: 0)
            let nameRange = match.range(at: 1)
            let name = ns.substring(with: nameRange)
            result += ns.substring(with: NSRange(location: cursor, length: whole.location - cursor))
            result += values[name] ?? ""
            cursor = whole.location + whole.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }
}
