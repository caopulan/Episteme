import Foundation

public struct ArxivFeedCacheStatus: Equatable, Sendable {
    public var date: String
    public var metadataCached: Bool
    public var cachedAssetCount: Int
    public var cachedPDFCount: Int

    public init(date: String, metadataCached: Bool, cachedAssetCount: Int, cachedPDFCount: Int) {
        self.date = date
        self.metadataCached = metadataCached
        self.cachedAssetCount = cachedAssetCount
        self.cachedPDFCount = cachedPDFCount
    }
}

public final class ArxivCacheDataStore {
    private let database: SQLiteDatabase
    private let dates = ISO8601DateFormatter()
    private let now: () -> Date

    public init(database: SQLiteDatabase, now: @escaping () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    public func upsertFeedDate(
        date: String,
        source: String,
        feedVersion: String?,
        filterSnapshotJSON: String?,
        cachedAt: Date,
        expiresAt: Date?
    ) throws {
        try database.run("""
        INSERT INTO arxiv_feed_dates (date, source, feed_version, filter_snapshot_json, cached_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
          source = excluded.source,
          feed_version = excluded.feed_version,
          filter_snapshot_json = excluded.filter_snapshot_json,
          cached_at = excluded.cached_at,
          expires_at = excluded.expires_at;
        """, bindings: [
            .text(date),
            .text(source),
            feedVersion.map(SQLiteValue.text) ?? .null,
            filterSnapshotJSON.map(SQLiteValue.text) ?? .null,
            .text(dates.string(from: cachedAt)),
            expiresAt.map { .text(dates.string(from: $0)) } ?? .null
        ])
    }

    public func upsertPDFCache(
        arxivID: String,
        date: String,
        localPath: String,
        contentHash: String?,
        byteCount: Int64?,
        cachedAt: Date,
        lastAccessedAt: Date?,
        promotedPaperID: String?
    ) throws {
        try database.run("""
        INSERT INTO arxiv_pdf_cache (
          arxiv_id, date, local_path, content_hash, byte_count, cached_at, last_accessed_at, promoted_paper_id
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(arxiv_id) DO UPDATE SET
          date = excluded.date,
          local_path = excluded.local_path,
          content_hash = excluded.content_hash,
          byte_count = excluded.byte_count,
          cached_at = excluded.cached_at,
          last_accessed_at = excluded.last_accessed_at,
          promoted_paper_id = excluded.promoted_paper_id;
        """, bindings: [
            .text(arxivID),
            .text(date),
            .text(localPath),
            contentHash.map(SQLiteValue.text) ?? .null,
            byteCount.map(SQLiteValue.int64) ?? .null,
            .text(dates.string(from: cachedAt)),
            lastAccessedAt.map { .text(dates.string(from: $0)) } ?? .null,
            promotedPaperID.map(SQLiteValue.text) ?? .null
        ])
    }

    public func feedCacheStatus(date: String) throws -> ArxivFeedCacheStatus {
        let metadataExpirations = try database.query(
            "SELECT expires_at FROM arxiv_feed_dates WHERE date = ?;",
            bindings: [.text(date)]
        ) { row in
            row.optionalText(0)
        }
        let assetCount = try database.query(
            "SELECT COUNT(*) FROM arxiv_assets WHERE date = ? AND local_path IS NOT NULL;",
            bindings: [.text(date)]
        ) { row in
            row.int(0)
        }.first ?? 0
        let pdfCount = try database.query(
            "SELECT COUNT(*) FROM arxiv_pdf_cache WHERE date = ?;",
            bindings: [.text(date)]
        ) { row in
            row.int(0)
        }.first ?? 0
        let metadataCached: Bool
        if let metadataExpiration = metadataExpirations.first {
            metadataCached = try metadataIsCurrent(expiresAt: metadataExpiration)
        } else {
            metadataCached = false
        }

        return ArxivFeedCacheStatus(
            date: date,
            metadataCached: metadataCached,
            cachedAssetCount: assetCount,
            cachedPDFCount: pdfCount
        )
    }

    private func metadataIsCurrent(expiresAt: String?) throws -> Bool {
        guard let expiresAt else {
            return true
        }
        guard let expirationDate = dates.date(from: expiresAt) else {
            throw PaperRepositoryError.decodingFailed("Invalid ISO8601 date: \(expiresAt)")
        }
        return expirationDate > now()
    }
}
