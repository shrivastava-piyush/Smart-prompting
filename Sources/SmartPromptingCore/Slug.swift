import Foundation

public enum Slug {
    /// Turns a title into a filesystem-safe slug: lowercase ASCII with hyphens.
    public static func make(from text: String, maxLength: Int = 60) -> String {
        let lower = text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        var chars: [Character] = []
        var lastWasHyphen = true
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                chars.append(ch)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                chars.append("-")
                lastWasHyphen = true
            }
        }
        while chars.last == "-" { chars.removeLast() }
        var slug = String(chars)
        if slug.isEmpty { slug = "prompt" }
        if slug.count > maxLength {
            slug = String(slug.prefix(maxLength))
            while slug.hasSuffix("-") { slug.removeLast() }
        }
        return slug
    }

    /// Appends an incrementing suffix until the candidate path doesn't exist.
    public static func uniqueSlug(base: String, in dir: URL) -> String {
        let isScoped = dir.startAccessingSecurityScopedResource()
        defer { if isScoped { dir.stopAccessingSecurityScopedResource() } }
        
        let fm = FileManager.default
        var candidate = base
        var i = 2
        while fm.fileExists(atPath: dir.appendingPathComponent("\(candidate).md").path) {
            candidate = "\(base)-\(i)"
            i += 1
        }
        return candidate
    }
}
