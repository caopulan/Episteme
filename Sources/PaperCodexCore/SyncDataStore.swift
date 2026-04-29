import Foundation

public final class SyncDataStore {
    private let database: SQLiteDatabase
    private let dates = ISO8601DateFormatter()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func markDirty(entityType: String, entityID: String, localRevision: Int, deleted: Bool, at date: Date) throws {
        try database.run("""
        INSERT INTO sync_entities (entity_type, entity_id, local_revision, remote_revision, dirty, deleted, last_synced_at)
        VALUES (?, ?, ?, NULL, 1, ?, NULL)
        ON CONFLICT(entity_type, entity_id) DO UPDATE SET
          local_revision = excluded.local_revision,
          dirty = 1,
          deleted = excluded.deleted;
        """, bindings: [
            .text(entityType),
            .text(entityID),
            .int(localRevision),
            .int(deleted ? 1 : 0)
        ])
        _ = date
    }

    public func enqueue(
        id: String,
        entityType: String,
        entityID: String,
        operation: String,
        payloadJSON: String,
        baseRemoteRevision: Int?,
        createdAt: Date
    ) throws {
        try database.run("""
        INSERT INTO sync_outbox (id, entity_type, entity_id, operation, payload_json, base_remote_revision, created_at, attempt_count, last_error)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, NULL)
        ON CONFLICT(id) DO NOTHING;
        """, bindings: [
            .text(id),
            .text(entityType),
            .text(entityID),
            .text(operation),
            .text(payloadJSON),
            baseRemoteRevision.map(SQLiteValue.int) ?? .null,
            .text(dates.string(from: createdAt))
        ])
    }

    public func setCursor(scope: String, cursor: String, updatedAt: Date) throws {
        try database.run("""
        INSERT INTO sync_cursors (scope, cursor, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(scope) DO UPDATE SET
          cursor = excluded.cursor,
          updated_at = excluded.updated_at;
        """, bindings: [
            .text(scope),
            .text(cursor),
            .text(dates.string(from: updatedAt))
        ])
    }

    public func fetchDirtyEntityIDs(entityType: String) throws -> [String] {
        try database.query("""
        SELECT entity_id
        FROM sync_entities
        WHERE entity_type = ? AND dirty = 1
        ORDER BY entity_id;
        """, bindings: [.text(entityType)]) { row in
            try row.text(0)
        }
    }

    public func fetchPendingOutboxIDs() throws -> [String] {
        try database.query("""
        SELECT id
        FROM sync_outbox
        ORDER BY created_at, id;
        """) { row in
            try row.text(0)
        }
    }

    public func fetchCursor(scope: String) throws -> String? {
        try database.query("""
        SELECT cursor
        FROM sync_cursors
        WHERE scope = ?
        LIMIT 1;
        """, bindings: [.text(scope)]) { row in
            try row.text(0)
        }.first
    }
}
