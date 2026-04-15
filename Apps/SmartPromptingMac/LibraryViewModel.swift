import Foundation
import SwiftUI
import SmartPromptingCore

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [ScoredPrompt] = []
    @Published var allPrompts: [Prompt] = []
    @Published var status: String = ""
    @Published var selectedIndex: Int = 0

    private let sp: SmartPrompting?

    init() {
        do {
            self.sp = try SmartPrompting()
            refresh()
        } catch {
            self.sp = nil
            self.status = "Error: \(error.localizedDescription)"
        }
    }

    func refresh() {
        guard let sp = sp else { return }
        allPrompts = (try? sp.store.all()) ?? []
        search()
    }

    func search() {
        guard let sp = sp else { return }
        results = (try? sp.search.query(query, limit: 15)) ?? []
        selectedIndex = 0
    }

    func selectNext() {
        if selectedIndex < results.count - 1 { selectedIndex += 1 }
    }

    func selectPrevious() {
        if selectedIndex > 0 { selectedIndex -= 1 }
    }

    /// Copies the selected prompt to the clipboard, rendering placeholders if
    /// values are provided. Returns the rendered text for potential paste-injection.
    func useSelected(values: [String: String] = [:]) -> String? {
        guard selectedIndex < results.count else { return nil }
        let p = results[selectedIndex].prompt
        do {
            let text = try TemplateEngine.render(p.body, with: values)
            Clipboard.copy(text)
            try? sp?.store.recordUse(p)
            refresh()
            return text
        } catch {
            status = error.localizedDescription
            return nil
        }
    }

    func addFromText(_ body: String) async {
        guard let sp = sp, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let p = try await sp.create(from: body)
            status = "Saved: \(p.title)"
            refresh()
        } catch {
            status = error.localizedDescription
        }
    }

    func delete(_ prompt: Prompt) {
        try? sp?.store.delete(slug: prompt.slug)
        refresh()
    }
}
