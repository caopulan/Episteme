import Foundation

public enum GeneratedImageCollector {
    private static let generatedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "gif"
    ]

    public static func snapshot(in root: URL, fileManager: FileManager = .default) throws -> Set<String> {
        Set(try imageFiles(in: root, fileManager: fileManager).map { $0.standardizedFileURL.path })
    }

    public static func newImages(
        in root: URL,
        excluding previousSnapshot: Set<String>,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try imageFiles(in: root, fileManager: fileManager)
            .filter { !previousSnapshot.contains($0.standardizedFileURL.path) }
            .sorted { $0.path < $1.path }
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
}
