import Foundation
import PaperCodexCore

enum LibraryThumbnailLoader {
    static func load(
        supportRoot: URL,
        papers: [Paper],
        existing: [String: [URL]]
    ) -> [String: [URL]] {
        let thumbnailCache = PDFThumbnailCache(root: supportRoot.appendingPathComponent("thumbnails", isDirectory: true))
        let visibleIDs = Set(papers.map(\.id))
        var urlsByID = existing.filter { visibleIDs.contains($0.key) }
        for paper in papers where urlsByID[paper.id] == nil {
            if let urls = try? thumbnailCache.thumbnails(for: paper) {
                urlsByID[paper.id] = urls
            }
        }
        return urlsByID
    }
}
