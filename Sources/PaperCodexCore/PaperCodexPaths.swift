import Foundation

public enum PaperCodexPaths {
    public static let supportRootEnvironmentKey = "EPISTEME_SUPPORT_ROOT"
    public static let legacySupportRootEnvironmentKey = "PAPER_CODEX_SUPPORT_ROOT"
    public static let appSupportDirectoryName = "Episteme"
    public static let legacyAppSupportDirectoryName = "PaperCodex"

    public static func supportRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment[supportRootEnvironmentKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }

        if let override = environment[legacySupportRootEnvironmentKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }

        return resolvedApplicationSupportDirectory(applicationSupportDirectory, fileManager: fileManager)
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .standardizedFileURL
    }

    public static func migrateLegacySupportRootIfNeeded(
        to supportRoot: URL,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard supportRoot.lastPathComponent == appSupportDirectoryName else {
            return
        }

        let legacyRoot = resolvedApplicationSupportDirectory(applicationSupportDirectory, fileManager: fileManager)
            .appendingPathComponent(legacyAppSupportDirectoryName, isDirectory: true)
            .standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: legacyRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }
        guard !fileManager.fileExists(atPath: supportRoot.path) else {
            return
        }

        try fileManager.createDirectory(
            at: supportRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: legacyRoot, to: supportRoot)
    }

    private static func resolvedApplicationSupportDirectory(
        _ applicationSupportDirectory: URL?,
        fileManager: FileManager
    ) -> URL {
        (applicationSupportDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .standardizedFileURL
    }
}
