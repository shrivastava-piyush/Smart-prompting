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
        let firstLine = body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "untitled prompt"
        let title = String(firstLine.prefix(80))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AutoTagResult(
            title: title,
            slug: Slug.make(from: title),
            tags: [],
            placeholders: placeholders
        )
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
