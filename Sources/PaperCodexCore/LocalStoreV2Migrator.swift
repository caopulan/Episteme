import Foundation

public enum LocalStoreV2Migrator {
    public static func migrate(database: SQLiteDatabase) throws {
        try database.transaction {
            try createTables(database: database)
            try addPaperColumns(database: database)
            try addTagColumns(database: database)
            try backfillFolders(database: database)
            try backfillPaperFiles(database: database)
            try backfillPaperSources(database: database)
        }
    }

    private static func createTables(database: SQLiteDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS local_accounts (
          id TEXT PRIMARY KEY,
          remote_user_id TEXT,
          display_name TEXT NOT NULL,
          email TEXT,
          sync_enabled INTEGER NOT NULL DEFAULT 0,
          last_login_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS devices (
          id TEXT PRIMARY KEY,
          remote_device_id TEXT,
          name TEXT NOT NULL,
          public_key TEXT,
          created_at TEXT NOT NULL,
          revoked_at TEXT
        );

        CREATE TABLE IF NOT EXISTS paper_files (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          storage_state TEXT NOT NULL,
          local_path TEXT,
          content_hash TEXT NOT NULL,
          byte_count INTEGER,
          mime_type TEXT NOT NULL,
          remote_file_id TEXT,
          encryption_state TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS paper_sources (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          source_type TEXT NOT NULL,
          source_id TEXT,
          url TEXT,
          version TEXT,
          metadata_json TEXT,
          created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS folders (
          id TEXT PRIMARY KEY,
          parent_id TEXT REFERENCES folders(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          sort_order INTEGER NOT NULL,
          deleted_at TEXT,
          sync_revision INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS paper_folders (
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          folder_id TEXT NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
          created_at TEXT NOT NULL DEFAULT '',
          deleted_at TEXT,
          PRIMARY KEY (paper_id, folder_id)
        );

        CREATE TABLE IF NOT EXISTS paper_notes (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          anchor_id TEXT REFERENCES anchors(id) ON DELETE SET NULL,
          title TEXT NOT NULL,
          body_markdown TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          sync_revision INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS pdf_annotations (
          id TEXT PRIMARY KEY,
          paper_id TEXT NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
          anchor_id TEXT REFERENCES anchors(id) ON DELETE SET NULL,
          page INTEGER NOT NULL,
          kind TEXT NOT NULL,
          color TEXT,
          text TEXT,
          bbox_list_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          sync_revision INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS arxiv_feed_dates (
          date TEXT PRIMARY KEY,
          source TEXT NOT NULL,
          feed_version TEXT,
          filter_snapshot_json TEXT,
          cached_at TEXT NOT NULL,
          expires_at TEXT
        );

        CREATE TABLE IF NOT EXISTS arxiv_feed_items (
          date TEXT NOT NULL,
          arxiv_id TEXT NOT NULL,
          paper_json TEXT NOT NULL,
          sort_key REAL,
          similarity REAL,
          is_favorite INTEGER,
          cached_at TEXT NOT NULL,
          PRIMARY KEY (date, arxiv_id)
        );

        CREATE TABLE IF NOT EXISTS arxiv_assets (
          asset_key TEXT PRIMARY KEY,
          arxiv_id TEXT NOT NULL,
          date TEXT NOT NULL,
          kind TEXT NOT NULL,
          local_path TEXT,
          url TEXT NOT NULL,
          content_hash TEXT,
          byte_count INTEGER,
          cached_at TEXT NOT NULL,
          last_accessed_at TEXT
        );

        CREATE TABLE IF NOT EXISTS arxiv_pdf_cache (
          arxiv_id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          local_path TEXT NOT NULL,
          content_hash TEXT,
          byte_count INTEGER,
          cached_at TEXT NOT NULL,
          last_accessed_at TEXT,
          promoted_paper_id TEXT REFERENCES papers(id) ON DELETE SET NULL
        );

        CREATE TABLE IF NOT EXISTS sync_entities (
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          local_revision INTEGER NOT NULL DEFAULT 0,
          remote_revision INTEGER,
          dirty INTEGER NOT NULL DEFAULT 0,
          deleted INTEGER NOT NULL DEFAULT 0,
          last_synced_at TEXT,
          PRIMARY KEY (entity_type, entity_id)
        );

        CREATE TABLE IF NOT EXISTS sync_outbox (
          id TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          base_remote_revision INTEGER,
          created_at TEXT NOT NULL,
          attempt_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT
        );

        CREATE TABLE IF NOT EXISTS sync_cursors (
          scope TEXT PRIMARY KEY,
          cursor TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        """)
    }

    private static func addPaperColumns(database: SQLiteDatabase) throws {
        let columns = try database.tableColumns("papers")
        let additions: [(String, String)] = [
            ("canonical_key", "TEXT"),
            ("abstract", "TEXT"),
            ("source_kind", "TEXT"),
            ("arxiv_id", "TEXT"),
            ("arxiv_id_versioned", "TEXT"),
            ("doi", "TEXT"),
            ("deleted_at", "TEXT"),
            ("sync_revision", "INTEGER NOT NULL DEFAULT 0")
        ]
        for (name, definition) in additions where !columns.contains(name) {
            try database.execute("ALTER TABLE papers ADD COLUMN \(name) \(definition);")
        }
        try database.run("""
        UPDATE papers
        SET canonical_key = COALESCE(canonical_key, file_hash),
            source_kind = CASE
              WHEN source_url LIKE 'https://arxiv.org/%' THEN 'arxiv'
              WHEN source_url IS NOT NULL THEN 'url'
              ELSE COALESCE(source_kind, 'manual')
            END,
            sync_revision = COALESCE(sync_revision, 0)
        WHERE canonical_key IS NULL OR source_kind IS NULL;
        """)
    }

    private static func addTagColumns(database: SQLiteDatabase) throws {
        let columns = try database.tableColumns("tags")
        let additions: [(String, String)] = [
            ("parent_id", "TEXT REFERENCES tags(id) ON DELETE CASCADE"),
            ("color", "TEXT"),
            ("sort_order", "INTEGER NOT NULL DEFAULT 0"),
            ("deleted_at", "TEXT"),
            ("sync_revision", "INTEGER NOT NULL DEFAULT 0")
        ]
        for (name, definition) in additions where !columns.contains(name) {
            try database.execute("ALTER TABLE tags ADD COLUMN \(name) \(definition);")
        }
    }

    private static func backfillFolders(database: SQLiteDatabase) throws {
        try database.run("""
        INSERT OR IGNORE INTO folders (id, parent_id, name, sort_order, deleted_at, sync_revision)
        SELECT id, parent_id, name, sort_order, NULL, 0 FROM categories;
        """)
        try database.run("""
        INSERT OR IGNORE INTO paper_folders (paper_id, folder_id, created_at, deleted_at)
        SELECT paper_id, category_id, '', NULL FROM paper_categories;
        """)
    }

    private static func backfillPaperFiles(database: SQLiteDatabase) throws {
        try database.run("""
        INSERT OR IGNORE INTO paper_files (
          id, paper_id, storage_state, local_path, content_hash, byte_count, mime_type,
          remote_file_id, encryption_state, created_at, updated_at
        )
        SELECT
          'file:' || id || ':original',
          id,
          CASE WHEN is_saved = 1 THEN 'saved_local' ELSE 'cache_preview' END,
          file_path,
          file_hash,
          NULL,
          'application/pdf',
          NULL,
          'none',
          imported_at,
          updated_at
        FROM papers;
        """)
    }

    private static func backfillPaperSources(database: SQLiteDatabase) throws {
        try database.run("""
        INSERT OR IGNORE INTO paper_sources (id, paper_id, source_type, source_id, url, version, metadata_json, created_at)
        SELECT
          'source:' || id || ':primary',
          id,
          CASE
            WHEN source_url LIKE 'https://arxiv.org/%' THEN 'arxiv'
            WHEN source_url IS NOT NULL THEN 'url'
            ELSE 'manual'
          END,
          CASE
            WHEN source_url LIKE 'https://arxiv.org/abs/%' THEN replace(source_url, 'https://arxiv.org/abs/', '')
            WHEN source_url LIKE 'https://arxiv.org/pdf/%' THEN replace(replace(source_url, 'https://arxiv.org/pdf/', ''), '.pdf', '')
            ELSE NULL
          END,
          source_url,
          NULL,
          NULL,
          imported_at
        FROM papers
        WHERE source_url IS NOT NULL;
        """)
    }
}
