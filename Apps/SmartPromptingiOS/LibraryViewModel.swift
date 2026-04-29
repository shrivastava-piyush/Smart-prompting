import Foundation
import SwiftUI
import SmartPromptingCore

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [ScoredPrompt] = []
    @Published var allPrompts: [Prompt] = []
    @Published var toast: String = ""
    @Published var iCloudSyncing: Bool = false
    @Published var iCloudMessage: String = ""
    @Published var usageStats: PromptStore.UsageStats?

    let spInstance: SmartPrompting?
    private var sp: SmartPrompting? { spInstance }

    init() {
        self.spInstance = try? SmartPrompting()
        checkICloudStatus()
    }

    func checkICloudStatus() {
        let status = ICloudSync.status()
        switch status {
        case .syncing:
            iCloudSyncing = true
            iCloudMessage = ""
        case .local(_, let reason):
            iCloudSyncing = false
            iCloudMessage = reason
        }
    }

    func refresh() {
        guard let sp = sp else { return }
        try? sp.store.syncIndexFromDisk()
        allPrompts = (try? sp.store.all()) ?? []
        search()
        checkICloudStatus()
    }

    func search() {
        guard let sp = sp else { return }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = allPrompts.prefix(50).map {
                ScoredPrompt(prompt: $0, score: 0, ftsScore: 0, vectorScore: 0)
            }
            return
        }
        results = (try? sp.search.query(query, limit: 50)) ?? []
    }

    func copy(_ prompt: Prompt, values: [String: String] = [:]) {
        do {
            let text = try TemplateEngine.render(prompt.body, with: values)
            Clipboard.copy(text)
            try? sp?.store.recordUse(prompt)
            toast = "Copied: \(prompt.title)"
            refresh()
        } catch {
            toast = error.localizedDescription
        }
    }

    func delete(_ prompt: Prompt) {
        try? sp?.store.delete(slug: prompt.slug)
        refresh()
    }

    func loadStats() {
        guard let sp = sp else { return }
        usageStats = try? sp.store.stats()
    }

    func add(body: String) async {
        guard let sp = sp, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = try? await sp.create(from: body)
        refresh()
    }
}
