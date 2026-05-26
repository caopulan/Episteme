import Foundation

public enum GeneratedImageCollector {
    private static let generatedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "gif"
    ]

    public static func snapshot(
        in root: URL,
        codexThreadID: String? = nil,
        codexHome: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Set<String> {
        let roots = [root] + codexImageRoots(threadID: codexThreadID, codexHome: codexHome ?? defaultCodexHome())
        return Set(try roots.flatMap { try imageFiles(in: $0, fileManager: fileManager) }.map { $0.standardizedFileURL.path })
    }

    public static func newImages(
        in root: URL,
        excluding previousSnapshot: Set<String>,
        codexThreadID: String? = nil,
        codexHome: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let workspaceImages = try imageFiles(in: root, fileManager: fileManager)
            .filter { !previousSnapshot.contains($0.standardizedFileURL.path) }
        let codexImages = try codexImageRoots(threadID: codexThreadID, codexHome: codexHome ?? defaultCodexHome())
            .flatMap { try imageFiles(in: $0, fileManager: fileManager) }
            .filter { !previousSnapshot.contains($0.standardizedFileURL.path) }
        let copiedCodexImages = try codexImages.map {
            try copyIntoWorkspace($0, workspaceRoot: root, fileManager: fileManager)
        }
        return (workspaceImages + copiedCodexImages).sorted { $0.path < $1.path }
    }

    public static func markdown(for imageURLs: [URL]) -> String {
        imageURLs
            .map { "![Generated image](\($0.standardizedFileURL.path))" }
            .joined(separator: "\n\n")
    }

    private static func imageFiles(in root: URL, fileManager: FileManager) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard generatedImageExtensions.contains(ext) else {
                continue
            }
            urls.append(url)
        }
        return urls
    }

    private static func codexImageRoots(threadID: String?, codexHome: URL) -> [URL] {
        guard let threadID = threadID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !threadID.isEmpty else {
            return []
        }
        return [
            codexHome
                .appendingPathComponent("generated_images", isDirectory: true)
                .appendingPathComponent(threadID, isDirectory: true)
        ]
    }

    private static func defaultCodexHome() -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func copyIntoWorkspace(_ source: URL, workspaceRoot: URL, fileManager: FileManager) throws -> URL {
        let outputDirectory = workspaceRoot.appendingPathComponent("generated-images", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let sourceName = source.deletingPathExtension().lastPathComponent
        let sourceExtension = source.pathExtension
        var destination = outputDirectory.appendingPathComponent(source.lastPathComponent)
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            let fileName = sourceExtension.isEmpty ? "\(sourceName)-\(suffix)" : "\(sourceName)-\(suffix).\(sourceExtension)"
            destination = outputDirectory.appendingPathComponent(fileName)
            suffix += 1
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }
}
