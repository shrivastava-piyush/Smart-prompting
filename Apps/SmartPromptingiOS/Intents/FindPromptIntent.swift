import AppIntents
import Foundation
import SmartPromptingCore

/// "Hey Siri, find prompt <query> in Smart Prompting" — returns the top hit's body and copies to clipboard.
struct FindPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Prompt"
    static var description = IntentDescription("Search your saved prompts and copy the top match to the clipboard.")

    @Parameter(title: "Query")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find prompt matching \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let sp = try SmartPrompting()
        let hits = try sp.search.query(query, limit: 1)
        guard let top = hits.first else {
            return .result(value: "", dialog: "No prompts matched \(query).")
        }
        let rendered = try TemplateEngine.render(top.prompt.body, with: [:])
        Clipboard.copy(rendered)
        try? sp.store.recordUse(top.prompt)
        return .result(value: rendered, dialog: "Copied \(top.prompt.title).")
    }
}

struct UsePromptByTitleIntent: AppIntent {
    static var title: LocalizedStringResource = "Use Prompt By Title"

    @Parameter(title: "Slug")
    var slug: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let sp = try SmartPrompting()
        guard let p = try sp.store.get(slug: slug) else {
            throw SmartPromptingError.promptNotFound(slug)
        }
        let text = try TemplateEngine.render(p.body, with: [:])
        Clipboard.copy(text)
        try? sp.store.recordUse(p)
        return .result(value: text)
    }
}
