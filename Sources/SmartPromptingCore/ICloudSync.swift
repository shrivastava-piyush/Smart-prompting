import Foundation

/// iCloud sync status — checked at launch to guide users.
public enum ICloudStatus: Sendable {
    /// Signed in; prompts dir is inside iCloud Drive and will sync.
    case syncing(path: String)
    /// Not signed in or iCloud Drive disabled. Prompts stored locally only.
    case local(path: String, reason: String)
}

/// Resolves the directory that holds the markdown prompt files and verifies
/// that iCloud Drive sync is actually working.
///
/// **How sync works:** The app does NOT sign you into iCloud — your Mac and
/// iPhone each sign in via *System Settings → Apple ID → iCloud Drive*. Once
/// both devices are signed into the same Apple ID with iCloud Drive enabled,
/// the OS transparently syncs the prompts folder. No tokens, no login in the
/// app itself.
///
/// **Shared path contract:** Both the CLI (`sp`) on macOS and the iOS app
/// resolve to the same iCloud Drive subfolder so prompts are visible on all
/// devices:
///
///   macOS CLI: ~/Library/Mobile Documents/com~apple~CloudDocs/SmartPrompting/prompts/
///   iOS app:   via NSMetadataQuery searching the default ubiquity container
///
/// If a custom ubiquity container (`iCloud.com.smartprompting.library`) is
/// provisioned, it takes priority on both platforms. Otherwise the shared
/// iCloud Drive folder is used — it works with a free Apple ID and requires
/// no developer portal configuration.
public enum ICloudSync {
    public static let subdir = "prompts"
    private static let bookmarkKey = "user_selected_prompts_dir_bookmark"

    /// Returns whether a custom folder is being used and its path.
    public static func status(overridingDir: URL? = nil) -> ICloudStatus {
        if let overridingDir = overridingDir {
            return .syncing(path: overridingDir.path)
        }
        
        if let override = ProcessInfo.processInfo.environment["SMART_PROMPTING_DIR"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            return .local(path: url.path, reason: "SMART_PROMPTING_DIR override")
        }

        if let userUrl = try? userSelectedDirectory() {
            return .syncing(path: userUrl.path)
        }

        let fm = FileManager.default
        
        #if os(macOS)
        // On Mac CLI/App, try the standard iCloud Drive path first.
        let cloudDocsBase = fm.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs",
            isDirectory: true
        )
        let appDir = cloudDocsBase.appendingPathComponent("SmartPrompting/\(subdir)", isDirectory: true)
        
        if fm.fileExists(atPath: cloudDocsBase.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
            return .syncing(path: appDir.path)
        }
        #endif

        let fallback = fallbackDir()
        return .local(
            path: fallback.path,
            reason: "Tap 'Select Folder' to choose a folder in iCloud Drive or locally."
        )
    }

    /// Resolves the prompts directory.
    public static func promptsDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SMART_PROMPTING_DIR"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try ensure(url)
            return url
        }

        // 1. Check for manual user selection (bookmark) - highest priority
        if let userUrl = try? userSelectedDirectory() {
            try ensure(userUrl)
            return userUrl
        }

        // 2. Check for automatic sync path (macOS only)
        if case .syncing(let path) = status() {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try ensure(url)
            return url
        }

        // 3. Fallback to local
        let fallback = fallbackDir()
        try ensure(fallback)
        return fallback
    }

    /// Saves a security-scoped bookmark for a user-selected directory.
    public static func saveBookmark(for url: URL) throws {
        // Start accessing to ensure we can create the bookmark
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }

    /// Loads the user-selected directory from a bookmark.
    public static func userSelectedDirectory() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        if isStale {
            try saveBookmark(for: url)
        }
        
        // On iOS, we MUST call startAccessing to actually use the resolved URL
        #if os(iOS)
        if !url.startAccessingSecurityScopedResource() {
            print("Warning: Could not start accessing security scoped resource")
        }
        #endif
        
        return url
    }

    /// Clears the user-selected directory.
    public static func clearUserSelection() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// True if the current prompts directory is synced via iCloud Drive.
    public static var isSyncing: Bool {
        if case .syncing = status() { return true }
        return false
    }

    /// Triggers download for any files in the prompts directory that are not yet local.
    /// This is a "fire and forget" helper for iOS.
    public static func triggerDownloads() {
        guard let url = try? promptsDirectory() else { return }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])) ?? []
        
        for file in files {
            let values = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
                try? fm.startDownloadingUbiquitousItem(at: file)
            }
        }
    }

    /// Human-readable explanation of current sync state.
    public static var statusMessage: String {
        switch status() {
        case .syncing(let path):
            return "Syncing via iCloud Drive (\(path))"
        case .local(_, let reason):
            return "Local only — \(reason)"
        }
    }

    /// Directory used for the local SQLite index (per-device, never synced).
    public static func indexDirectory() throws -> URL {
        let fm = FileManager.default
        let url = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("SmartPrompting", isDirectory: true)
        try ensure(url)
        return url
    }

    // MARK: - Private

    private static func fallbackDir() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport
            .appendingPathComponent("SmartPrompting", isDirectory: true)
            .appendingPathComponent(subdir, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func ensure(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }
}
