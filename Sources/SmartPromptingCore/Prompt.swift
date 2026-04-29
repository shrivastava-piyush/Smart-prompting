import Foundation

/// A single stored prompt. The markdown file on disk is the source of truth;
/// a copy lives in the local SQLite index for search.
public struct Prompt: Codable, Equatable, Identifiable, Sendable {
    public var id: String                // stable UUID, used as filename seed
    public var slug: String              // human-readable filename stem
    public var title: String
    public var body: String              // raw prompt text (no frontmatter)
    public var tags: [String]
    public var placeholders: [String]    // parsed from {{name}}
    public var created: Date
    public var updated: Date
    public var useCount: Int
    public var lastUsed: Date?

    public init(
        id: String = UUID().uuidString,
        slug: String,
        title: String,
        body: String,
        tags: [String] = [],
        placeholders: [String] = [],
        created: Date = Date(),
        updated: Date = Date(),
        useCount: Int = 0,
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.body = body
        self.tags = tags
        self.placeholders = placeholders
        self.created = created
        self.updated = updated
        self.useCount = useCount
        self.lastUsed = lastUsed
    }
}

public struct ScoredPrompt: Sendable {
    public let prompt: Prompt
    public let score: Double
    public let ftsScore: Double
    public let vectorScore: Double

    public init(prompt: Prompt, score: Double, ftsScore: Double, vectorScore: Double) {
        self.prompt = prompt
        self.score = score
        self.ftsScore = ftsScore
        self.vectorScore = vectorScore
    }
}

public struct PromptVersion: Sendable {
    public let version: Int
    public let date: Date
    public let prompt: Prompt?

    public init(version: Int, date: Date, prompt: Prompt?) {
        self.version = version
        self.date = date
        self.prompt = prompt
    }
}

public enum SmartPromptingError: Error, LocalizedError {
    case promptNotFound(String)
    case missingPlaceholder(String)
    case iCloudUnavailable
    case invalidMarkdown(String)
    case embeddingUnavailable
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .promptNotFound(let id): return "Prompt not found: \(id)"
        case .missingPlaceholder(let name): return "Missing value for placeholder: {{\(name)}}"
        case .iCloudUnavailable: return "iCloud Drive is not available. Sign in and enable iCloud Drive in System Settings."
        case .invalidMarkdown(let reason): return "Invalid prompt markdown: \(reason)"
        case .embeddingUnavailable: return "Embedding model is not available on this device."
        case .apiError(let msg): return "AutoTag API error: \(msg)"
        }
    }
}
