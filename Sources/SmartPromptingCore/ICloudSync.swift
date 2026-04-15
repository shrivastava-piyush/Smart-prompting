import Foundation

/// Resolves the directory that holds the markdown prompt files.
///
/// Preference order:
/// 1. `SMART_PROMPTING_DIR` environment variable (useful for tests and CLI overrides).
/// 2. iCloud Drive ubiquity container for `iCloud.com.smartprompting.library`.
/// 3. `~/Library/Mobile Documents/com~apple~CloudDocs/SmartPrompting/prompts`
///    (iCloud Drive default folder, reachable even without a custom container).
/// 4. Fallback to `~/Library/Application Support/SmartPrompting/prompts`.
public enum ICloudSync {
    public static let ubiquityContainer = "iCloud.com.smartprompting.library"
    public static let subdir = "prompts"

    public static func promptsDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SMART_PROMPTING_DIR"] {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try ensure(url)
            return url
        }

        let fm = FileManager.default

        if let ubiq = fm.url(forUbiquityContainerIdentifier: ubiquityContainer) {
            let docs = ubiq.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(subdir, isDirectory: true)
            try ensure(docs)
            return docs
        }

        let home = fm.homeDirectoryForCurrentUser
        let cloudDocs = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/SmartPrompting/\(subdir)",
            isDirectory: true
        )
        if fm.fileExists(atPath: cloudDocs.deletingLastPathComponent().path)
            || canCreate(cloudDocs) {
            try ensure(cloudDocs)
            return cloudDocs
        }

        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("SmartPrompting/\(subdir)", isDirectory: true)
        try ensure(appSupport)
        return appSupport
    }

    /// Directory used for the local SQLite index (per-device, not synced).
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

    private static func ensure(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    private static func canCreate(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path)
    }
}
