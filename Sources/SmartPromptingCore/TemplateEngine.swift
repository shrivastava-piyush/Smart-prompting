import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Parses and renders {{placeholder}} templates.
///
/// Two kinds of variables:
/// 1. **System variables** — auto-resolve at render time, no user input needed:
///    `{{clipboard}}`, `{{today}}`, `{{now}}`, `{{hostname}}`, `{{year}}`,
///    `{{month}}`, `{{day}}`, `{{weekday}}`, `{{timestamp}}`, `{{uuid}}`.
/// 2. **User variables** — any other `{{name}}`; must be supplied via the
///    `values` dictionary or the user is prompted interactively.
///
/// Placeholder names match `[A-Za-z_][A-Za-z0-9_-]*`.
public enum TemplateEngine {
    private static let pattern = #"\{\{\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}"#

    /// Names of all system variables that auto-resolve.
    public static let systemVariableNames: Set<String> = [
        "clipboard", "today", "now", "hostname", "year", "month", "day",
        "weekday", "timestamp", "uuid",
    ]

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

    /// Placeholders that require user input (excludes system variables).
    public static func userPlaceholders(in body: String) -> [String] {
        placeholders(in: body).filter { !systemVariableNames.contains($0.lowercased()) }
    }

    /// Render the body by substituting all variables.
    /// System variables resolve automatically. User variables must be in `values`.
    /// Throws `missingPlaceholder` if a user variable has no value.
    public static func render(_ body: String, with values: [String: String]) throws -> String {
        let merged = mergeWithSystemValues(values)
        let names = placeholders(in: body)
        for name in names {
            let key = name.lowercased()
            if !systemVariableNames.contains(key) && merged[name] == nil {
                throw SmartPromptingError.missingPlaceholder(name)
            }
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
            if let val = merged[name] {
                result += val
            } else {
                // System variable (case-insensitive lookup)
                result += resolveSystemVariable(name) ?? ""
            }
            cursor = whole.location + whole.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }

    // MARK: - System variable resolution

    private static func mergeWithSystemValues(_ user: [String: String]) -> [String: String] {
        var merged = user
        for name in systemVariableNames {
            if merged[name] == nil, let val = resolveSystemVariable(name) {
                merged[name] = val
            }
        }
        return merged
    }

    /// Resolve a single system variable by name. Returns nil if not a system var.
    public static func resolveSystemVariable(_ name: String) -> String? {
        let key = name.lowercased()
        let now = Date()
        let cal = Calendar.current

        switch key {
        case "clipboard":
            return clipboardContents()
        case "today":
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: now)
        case "now":
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: now)
        case "hostname":
            return ProcessInfo.processInfo.hostName
        case "year":
            return String(cal.component(.year, from: now))
        case "month":
            let f = DateFormatter()
            f.dateFormat = "MMMM"
            return f.string(from: now)
        case "day":
            return String(cal.component(.day, from: now))
        case "weekday":
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: now)
        case "timestamp":
            return ISO8601DateFormatter().string(from: now)
        case "uuid":
            return UUID().uuidString
        default:
            return nil
        }
    }

    private static func clipboardContents() -> String {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return NSPasteboard.general.string(forType: .string) ?? ""
        #elseif canImport(UIKit)
        return UIPasteboard.general.string ?? ""
        #else
        return ""
        #endif
    }
}
