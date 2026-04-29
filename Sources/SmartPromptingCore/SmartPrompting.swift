import Foundation

/// Umbrella facade tying the pieces together. One instance is enough per process.
public final class SmartPrompting: @unchecked Sendable {
    public let store: PromptStore
    public let search: Search
    public let autoTag: AutoTag
    public let assembly: AssemblyEngine

    public init(
        promptsDir: URL? = nil,
        indexDir: URL? = nil,
        embeddings: Embeddings = .shared,
        autoTag: AutoTag = .shared
    ) throws {
        self.store = try PromptStore(promptsDir: promptsDir, indexDir: indexDir, embeddings: embeddings)
        self.search = Search(store: store, embeddings: embeddings)
        self.autoTag = autoTag
        self.assembly = AssemblyEngine(store: store, search: search)
    }

    /// Create a new prompt from raw text, asking AutoTag for a title/tags/slug.
    public func create(from body: String, titleHint: String? = nil) async throws -> Prompt {
        let tagged = await autoTag.tag(body: body)
        let finalTitle = titleHint ?? tagged.title
        let prompt = Prompt(
            slug: tagged.slug.isEmpty ? Slug.make(from: finalTitle) : tagged.slug,
            title: finalTitle,
            body: body,
            tags: tagged.tags,
            placeholders: tagged.placeholders
        )
        return try store.add(prompt)
    }

    /// Render a prompt with placeholder values and record the usage.
    public func use(_ prompt: Prompt, values: [String: String] = [:]) throws -> String {
        let rendered = try TemplateEngine.render(prompt.body, with: values)
        try store.recordUse(prompt)
        return rendered
    }
}
