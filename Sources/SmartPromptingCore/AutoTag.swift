import Foundation

/// Generates a title, slug, tags, and placeholder list for a raw prompt body.
///
/// If an `ANTHROPIC_API_KEY` is available, calls Claude Haiku once.
/// Otherwise falls back to deterministic local heuristics.
public struct AutoTagResult: Sendable, Equatable {
    public var title: String
    public var slug: String
    public var tags: [String]
    public var placeholders: [String]
}

public final class AutoTag: @unchecked Sendable {
    public static let shared = AutoTag()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func tag(body: String) async -> AutoTagResult {
        let localPlaceholders = TemplateEngine.placeholders(in: body)

        if let key = KeychainConfig.anthropicAPIKey(),
           let remote = try? await callAnthropic(body: body, apiKey: key) {
            var r = remote
            // Trust locally-parsed placeholders over the model (it may hallucinate).
            r.placeholders = localPlaceholders
            if r.slug.isEmpty { r.slug = Slug.make(from: r.title) }
            return r
        }

        return localFallback(body: body, placeholders: localPlaceholders)
    }

    // MARK: - Local fallback

    private func localFallback(body: String, placeholders: [String]) -> AutoTagResult {
        let title = Self.synthesizeTitle(from: body)
        let tags = Self.extractTags(from: body)
        return AutoTagResult(
            title: title,
            slug: Slug.make(from: title),
            tags: tags,
            placeholders: placeholders
        )
    }

    /// Build a short descriptive title from the body instead of just copying the first line.
    /// Strategy: find the dominant action verb + object noun phrase, then title-case it.
    static func synthesizeTitle(from body: String) -> String {
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Untitled Prompt" }

        let words = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        // If it's very short (<=6 words), just use it directly as the title.
        if words.count <= 6 {
            return String(cleaned.prefix(60))
        }

        // Extract the first imperative sentence or clause (up to first period,
        // newline, or "—" / ":" delimiter).
        let firstClause: String = {
            let delimiters = CharacterSet(charactersIn: ".!?\n:—–")
            let parts = cleaned.unicodeScalars.split(whereSeparator: { delimiters.contains($0) })
            return parts.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? cleaned
        }()

        // Strip leading filler like "Please", "You are", "I want you to",
        // "You should", "Can you" to get to the actionable core.
        let fillerPrefixes = [
            "please ", "i want you to ", "i need you to ", "i'd like you to ",
            "can you ", "could you ", "you are ", "you're ", "act as ",
            "you will ", "you should ", "your task is to ", "your job is to ",
            "i want ", "i need ", "help me ", "help us ",
        ]
        var core = firstClause
        for prefix in fillerPrefixes {
            if core.lowercased().hasPrefix(prefix) {
                core = String(core.dropFirst(prefix.count))
                break
            }
        }
        core = core.trimmingCharacters(in: .whitespacesAndNewlines)
        if core.isEmpty { core = firstClause }

        // Truncate to ~60 chars on a word boundary.
        if core.count > 60 {
            let truncated = core.prefix(60)
            if let lastSpace = truncated.lastIndex(of: " ") {
                core = String(truncated[..<lastSpace])
            } else {
                core = String(truncated)
            }
        }

        // Title-case: capitalize the first letter of each significant word.
        let minor: Set<String> = ["a", "an", "the", "and", "or", "but", "in",
                                   "on", "at", "to", "for", "of", "with", "by"]
        let titled = core.split(separator: " ").enumerated().map { idx, word in
            let w = String(word)
            if idx == 0 || !minor.contains(w.lowercased()) {
                return w.prefix(1).uppercased() + w.dropFirst().lowercased()
            }
            return w.lowercased()
        }.joined(separator: " ")

        return titled.isEmpty ? "Untitled Prompt" : titled
    }

    /// Pull a handful of keyword-tags from the body using simple TF heuristics.
    static func extractTags(from body: String) -> [String] {
        let stop: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "shall",
            "should", "may", "might", "must", "can", "could", "i", "you", "he",
            "she", "it", "we", "they", "me", "him", "her", "us", "them", "my",
            "your", "his", "its", "our", "their", "this", "that", "these", "those",
            "and", "but", "or", "nor", "not", "so", "yet", "both", "either",
            "neither", "each", "every", "all", "any", "few", "more", "most",
            "other", "some", "such", "no", "only", "own", "same", "than", "too",
            "very", "just", "because", "as", "until", "while", "of", "at", "by",
            "for", "with", "about", "against", "between", "through", "during",
            "before", "after", "above", "below", "to", "from", "up", "down",
            "in", "out", "on", "off", "over", "under", "again", "further",
            "then", "once", "here", "there", "when", "where", "why", "how",
            "what", "which", "who", "whom", "if", "please", "make", "use",
            "also", "like", "want", "need", "get", "let", "sure", "well",
        ]
        let words = body.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 3 && !stop.contains($0) }

        var freq: [String: Int] = [:]
        for w in words { freq[w, default: 0] += 1 }
        let top = freq.sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)
        return top
    }

    // MARK: - Anthropic call

    private struct AnthropicRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct AnthropicResponse: Decodable {
        let content: [Block]
        struct Block: Decodable { let type: String; let text: String? }
    }

    private struct ModelJSON: Decodable {
        let title: String
        let slug: String?
        let tags: [String]
        let placeholders: [String]?
    }

    private func callAnthropic(body: String, apiKey: String) async throws -> AutoTagResult {
        let system = """
            You label a reusable LLM prompt. Return ONLY minified JSON with keys:
            "title" (<=60 chars, Title Case, no quotes),
            "slug" (kebab-case, <=40 chars),
            "tags" (3-5 lowercase short strings),
            "placeholders" (list of {{name}} variables found in the body).
            No prose, no code fences, no trailing commentary.
            """
        let req = AnthropicRequest(
            model: "claude-haiku-4-5",
            max_tokens: 300,
            system: system,
            messages: [.init(role: "user", content: body)]
        )

        var urlReq = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "content-type")
        urlReq.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlReq.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlReq.httpBody = try JSONEncoder().encode(req)

        let (data, response) = try await session.data(for: urlReq)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SmartPromptingError.apiError("HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw SmartPromptingError.apiError("no text block")
        }
        let jsonData = Data(text.utf8)
        let parsed = try JSONDecoder().decode(ModelJSON.self, from: jsonData)
        return AutoTagResult(
            title: parsed.title,
            slug: parsed.slug ?? Slug.make(from: parsed.title),
            tags: parsed.tags,
            placeholders: parsed.placeholders ?? TemplateEngine.placeholders(in: body)
        )
    }
}
