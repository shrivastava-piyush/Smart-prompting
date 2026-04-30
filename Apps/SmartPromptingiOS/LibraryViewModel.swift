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
    private var refreshTimer: Timer?

    private final class WatcherState {
        var watcher: DispatchSourceFileSystemObject?
        var descriptor: Int32 = -1

        func stop() {
            watcher?.cancel()
            watcher = nil
            if descriptor != -1 {
                close(descriptor)
                descriptor = -1
            }
        }
    }

    private let watcherState = WatcherState()

    init() {
        self.spInstance = try? SmartPrompting()
        checkICloudStatus()
        setupWatcher()
        startTimer()
    }

    deinit {
        watcherState.stop()
        refreshTimer?.invalidate()
    }

    func selectDirectory(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            toast = "Permission denied for this folder."
            return
        }

        do {
            try ICloudSync.saveBookmark(for: url)
            watcherState.stop()
            setupWatcher()
            refresh()
            toast = "Syncing with selected folder"
        } catch {
            toast = "Failed to select directory: \(error.localizedDescription)"
        }
    }

    func resetDirectory() {
        ICloudSync.clearUserSelection()
        watcherState.stop()
        setupWatcher()
        refresh()
        toast = "Reset to default local storage"
    }

    func forceSync() {
        guard let sp = sp else { return }
        toast = "Re-indexing..."
        try? FileManager.default.removeItem(at: sp.store.dbURL)
        do {
            refresh()
            toast = "Re-indexed \(allPrompts.count) prompts"
        } catch {
            toast = "Re-index failed: \(error.localizedDescription)"
        }
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func setupWatcher() {
        guard let url = sp?.store.promptsDir else { return }

        watcherState.stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd != -1 else { return }
        watcherState.descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global()
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }

        source.resume()
        watcherState.watcher = source
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
        ICloudSync.triggerDownloads()
        try? sp.store.syncIndexFromDisk()

        let fetched = (try? sp.store.all()) ?? []
        if fetched.count != allPrompts.count ||
           fetched.map(\.id) != allPrompts.map(\.id) ||
           fetched.map(\.updated) != allPrompts.map(\.updated) {
            allPrompts = fetched
            search()
        }
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
        do {
            try sp?.store.delete(slug: prompt.slug)
            refresh()
            toast = "Deleted: \(prompt.title)"
        } catch {
            toast = "Delete failed: \(error.localizedDescription)"
        }
    }

    func loadStats() {
        guard let sp = sp else { return }
        usageStats = try? sp.store.stats()
    }

    func add(title: String, body: String) async {
        guard let sp = sp, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            _ = try await sp.create(from: body, titleHint: title)
            refresh()
            toast = "Saved: \(title)"
        } catch {
            toast = "Save failed: \(error.localizedDescription)"
        }
    }
}
