import CryptoKit
import Foundation

public struct PaperImportResult: Equatable, Sendable {
    public var paper: Paper
    public var didImport: Bool

    public init(paper: Paper, didImport: Bool) {
        self.paper = paper
        self.didImport = didImport
    }
}

public final class PaperLibraryImporter {
    private let repository: PaperRepository
    private let supportRoot: URL
    private let fileManager: FileManager

    public init(repository: PaperRepository, supportRoot: URL, fileManager: FileManager = .default) {
        self.repository = repository
        self.supportRoot = supportRoot
        self.fileManager = fileManager
    }

    public func importPDF(
        from sourceURL: URL,
        metadata: PaperImportMetadata? = nil,
        isSaved: Bool = true,
        storageSubpath: String? = nil,
        storageRoot: URL? = nil,
        now: Date = Date()
    ) throws -> PaperImportResult {
        let standardizedSource = sourceURL.standardizedFileURL
        let data = try Data(contentsOf: standardizedSource)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = try repository.fetchPaper(fileHash: hash) {
            let enriched = try enrichedDuplicatePaper(
                existing,
                metadata: metadata,
                isSaved: isSaved,
                storageSubpath: storageSubpath,
                storageRoot: storageRoot,
                now: now
            )
            if enriched != existing {
                try repository.upsertPaper(enriched)
            }
            return PaperImportResult(paper: enriched, didImport: false)
        }

        let fallbackTitle = standardizedSource.deletingPathExtension().lastPathComponent
        let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackTitle
        let paperID = makePaperID(title: title, hash: hash)
        let paperDir = paperDirectory(
            paperID: paperID,
            storageSubpath: storageSubpath,
            storageRoot: storageRoot,
            isSaved: isSaved
        )
        try fileManager.createDirectory(at: paperDir, withIntermediateDirectories: true)
        let destination = paperDir.appendingPathComponent("original.pdf")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try data.write(to: destination, options: [.atomic])

        let index = try PDFIndexExtractor().extract(paperID: paperID, pdfURL: destination)
        let paper = Paper(
            id: paperID,
            filePath: destination.path,
            fileHash: hash,
            title: title,
            authors: metadata?.authors ?? [],
            year: metadata?.year,
            sourceURL: metadata?.sourceURL,
            isSaved: isSaved,
            importedAt: now,
            updatedAt: now
        )
        try repository.upsertPaper(paper)
        for page in index.pages {
            try repository.upsertPage(page)
        }
        for span in index.spans {
            try repository.upsertSpan(span)
        }

        return PaperImportResult(paper: paper, didImport: true)
    }

    private func makePaperID(title: String, hash: String) -> String {
        let slug = makeSlug(from: title)
        return "\(slug.isEmpty ? "paper" : slug)-\(hash.prefix(10))"
    }

    private func makeSlug(from text: String) -> String {
        text
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func enrichedDuplicatePaper(
        _ paper: Paper,
        metadata: PaperImportMetadata?,
        isSaved: Bool,
        storageSubpath: String?,
        storageRoot: URL?,
        now: Date
    ) throws -> Paper {
        guard let metadata else {
            var updated = paper
            if isSaved, !updated.isSaved {
                updated.filePath = try promotedFilePath(
                    paper: updated,
                    storageSubpath: storageSubpath,
                    storageRoot: storageRoot
                )
                updated.isSaved = true
                updated.updatedAt = now
            }
            return updated
        }

        var enriched = paper
        if let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            enriched.title = title
        }
        if !metadata.authors.isEmpty {
            enriched.authors = metadata.authors
        }
        if let year = metadata.year {
            enriched.year = year
        }
        if let sourceURL = metadata.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            enriched.sourceURL = sourceURL
        }
        if isSaved, !enriched.isSaved {
            enriched.filePath = try promotedFilePath(
                paper: enriched,
                storageSubpath: storageSubpath,
                storageRoot: storageRoot
            )
            enriched.isSaved = true
        }
        if enriched != paper {
            enriched.updatedAt = now
        }
        return enriched
    }

    private func promotedFilePath(paper: Paper, storageSubpath: String?, storageRoot: URL?) throws -> String {
        let paperDir = paperDirectory(
            paperID: paper.id,
            storageSubpath: storageSubpath,
            storageRoot: storageRoot,
            isSaved: true
        )
        try fileManager.createDirectory(at: paperDir, withIntermediateDirectories: true)
        let destination = paperDir.appendingPathComponent("original.pdf")
        let source = URL(fileURLWithPath: paper.filePath).standardizedFileURL
        if source != destination.standardizedFileURL {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }
        return destination.path
    }

    private func paperDirectory(
        paperID: String,
        storageSubpath: String?,
        storageRoot: URL?,
        isSaved: Bool
    ) -> URL {
        let root = storageRoot ?? supportRoot.appendingPathComponent(isSaved ? "papers" : "cache/papers", isDirectory: true)
        let safeComponents = safePathComponents(storageSubpath)
        let parent = safeComponents.reduce(root) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
        return parent.appendingPathComponent(paperID, isDirectory: true)
    }

    private func safePathComponents(_ rawPath: String?) -> [String] {
        guard let rawPath else {
            return []
        }
        return rawPath
            .split(separator: "/")
            .map { makeSlug(from: String($0)) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
