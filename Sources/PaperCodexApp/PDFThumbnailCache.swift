import AppKit
import PaperCodexCore
import PDFKit

final class PDFThumbnailCache {
    private let root: URL
    private let fileManager: FileManager

    init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    func thumbnails(for paper: Paper, pageLimit: Int = 5) throws -> [URL] {
        try thumbnails(
            forPDFAt: URL(fileURLWithPath: paper.filePath),
            cacheID: paper.id,
            pageLimit: pageLimit,
            size: CGSize(width: 86, height: 112)
        )
    }

    func thumbnails(
        forPDFAt pdfURL: URL,
        cacheID: String,
        pageLimit: Int = 5,
        size: CGSize = CGSize(width: 160, height: 208)
    ) throws -> [URL] {
        let directory = root.appendingPathComponent(safeCacheID(cacheID), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (1...pageLimit).map { directory.appendingPathComponent(String(format: "p%03d.png", $0)) }
        if existing.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) {
            return existing
        }

        guard let document = PDFDocument(url: pdfURL) else {
            return []
        }
        var urls: [URL] = []
        let count = min(pageLimit, document.pageCount)
        for index in 0..<count {
            guard let page = document.page(at: index) else {
                continue
            }
            let image = page.thumbnail(of: size, for: .cropBox)
            guard let data = image.pngData else {
                continue
            }
            let url = directory.appendingPathComponent(String(format: "p%03d.png", index + 1))
            try data.write(to: url, options: [.atomic])
            urls.append(url)
        }
        return urls
    }

    private func safeCacheID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || ".-_".unicodeScalars.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("-")
            }
        }
        return result.isEmpty ? "pdf" : result
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
