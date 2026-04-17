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
    public static let customContainer = "iCloud.com.smartprompting.library"
    public static let subdir = "prompts"

    // MARK: - Status check

    /// Returns whether iCloud Drive is available and where prompts will be stored.
    public static func status() -> ICloudStatus {
        if let override = ProcessInfo.processInfo.environment["SMART_PROMPTING_DIR"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            return .local(path: url.path, reason: "SMART_PROMPTING_DIR override")
        }

        let fm = FileManager.default

        // Check 1: is there an iCloud identity token at all?
        guard fm.ubiquityIdentityToken != nil else {
            let fallback = fallbackDir()
            return .local(
                path: fallback.path,
                reason: "Not signed into iCloud. Go to System Settings → Apple ID → iCloud Drive and sign in."
            )
        }

        // Check 2: can we resolve a custom ubiquity container?
        if let ubiq = fm.url(forUbiquityContainerIdentifier: customContainer) {
            let docs = ubiq
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(subdir, isDirectory: true)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            return .syncing(path: docs.path)
        }

        // Check 3: default iCloud Drive folder (com~apple~CloudDocs).
        let home = fm.homeDirectoryForCurrentUser
        let cloudDocs = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/SmartPrompting/\(subdir)",
            isDirectory: true
        )
        if fm.isWritableFile(atPath: cloudDocs.deletingLastPathComponent().deletingLastPathComponent().path) {
            try? fm.createDirectory(at: cloudDocs, withIntermediateDirectories: true)
            return .syncing(path: cloudDocs.path)
        }

        // Check 4: on iOS, try the default ubiquity container (nil identifier).
        if let ubiq = fm.url(forUbiquityContainerIdentifier: nil) {
            let docs = ubiq
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(subdir, isDirectory: true)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            return .syncing(path: docs.path)
        }

        // Fallback: local-only.
        let fallback = fallbackDir()
        return .local(
            path: fallback.path,
            reason: "iCloud Drive folder not writable. Check System Settings → Apple ID → iCloud Drive."
        )
    }

    /// Resolves the prompts directory. Prefers iCloud, falls back to local.
    public static func promptsDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SMART_PROMPTING_DIR"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try ensure(url)
            return url
        }

        switch status() {
        case .syncing(let path):
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try ensure(url)
            return url
        case .local(let path, _):
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try ensure(url)
            return url
        }
    }

    /// True if the current prompts directory is synced via iCloud Drive.
    public static var isSyncing: Bool {
        if case .syncing = status() { return true }
        return false
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
