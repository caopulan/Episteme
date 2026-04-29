# Paper Codex Data Backend Redesign

Date: 2026-04-29
Status: proposed design for user review

## Goal

Redesign Paper Codex's data layer so the app is useful offline, syncs a user's library online, supports real user login, and keeps paper PDFs, arXiv feed caches, tags, notes, anchors, and Codex reading sessions under clear security and ownership rules.

The product remains local-first: the macOS app must continue to open saved PDFs, cached arXiv feeds, notes, tags, source anchors, and recent Codex session context without a network connection. Online services add login, sync, feed enrichment, recommendations, and optional backup; they must not become required for normal reading of already-local papers.

## Current State

- Local SQLite stores saved papers, categories, flat tags, page text, spans, anchors, sessions, session papers, chat messages, and watched folders.
- Paper files live under Application Support: saved PDFs under `papers/`, unsaved opened arXiv PDFs under `cache/papers/`, arXiv feed JSON/assets under `arxiv-cache/`, and transient downloads under `cache/downloads/`.
- CodeArXiv is currently the remote feed and preference service. Paper Codex stores its base URL, username, and token in `UserDefaults`.
- The app can decode daily feed metadata, cache thumbnails, download PDFs, migrate favorites, and keep five-page library thumbnails.
- Publish-time risks remain: insecure HTTP defaults, an App Transport Security exception for the test host, token storage in `UserDefaults`, possible auth forwarding to arbitrary absolute asset URLs, and remote MathJax loading.

## Product Requirements

### Online And Offline

- The app opens and searches the saved local library offline.
- The app opens cached arXiv daily feeds offline for any date previously cached.
- The app opens cached arXiv thumbnails and large preview images offline.
- The app can optionally prefetch every PDF for selected arXiv feed dates.
- Offline edits to library metadata, tags, folders, notes, anchors, and reading sessions are queued and synced when connectivity returns.
- The app must clearly distinguish a disposable cache miss from a saved-library missing file.

### User Login And Sync

- Users can sign in from the app.
- A signed-in user gets online sync for library metadata, folders, hierarchical tags, notes, source anchors, reading annotations, and CodeArXiv preferences.
- The app supports multiple local devices for one user.
- The app can continue in local-only mode without login.
- Tokens and refresh credentials are stored in Keychain, not in `UserDefaults`.

### Library Data

- Papers have stable identities independent of local file path.
- arXiv papers are deduplicated by normalized arXiv ID, versioned arXiv ID, canonical abs URL, PDF URL, and file hash.
- Non-arXiv papers are deduplicated by file hash, DOI, URL, and optional user-confirmed metadata.
- Tags are hierarchical and can be attached to papers.
- Categories/folders remain hierarchical and represent organization, while tags represent facets.
- Notes are first-class data, not hidden inside chat messages.
- User-created anchors, PDF highlights, and notes are synced as independent entities.

### Security

- Release builds use HTTPS only. HTTP and host-specific ATS exceptions are development-only.
- The app attaches Authorization headers only to the configured product API origin, never to arbitrary absolute asset or PDF URLs.
- The backend checks user ownership on every object. `username`, `paper_id`, `arxiv_id`, or sync cursors from the client are never trusted as authorization.
- Edge or reverse-proxy products may hide and protect the origin, but they are not the security boundary by themselves.

## Architecture

Paper Codex should split data into four explicit layers.

### 1. Local App Store

The macOS app owns the offline-capable SQLite database and local file store.

Responsibilities:

- Store all saved library metadata and sync state.
- Store feed manifests and cache indexes.
- Store local files, thumbnails, extracted text, spans, anchors, notes, and Codex session records.
- Queue local changes in a sync outbox.
- Apply remote changes from a sync inbox.
- Enforce local cache policies and storage budgets.

Recommended module boundaries:

- `LocalStore`: SQLite migrations and typed repositories.
- `LibraryDataStore`: papers, folders, hierarchical tags, notes, anchors, annotations, sessions.
- `ArxivCacheStore`: daily feed manifests, feed items, feed assets, optional feed PDF cache.
- `FileStore`: content-addressed file placement, movement between disposable cache and saved library, missing-file repair.
- `SyncStore`: sync cursors, local revisions, tombstones, outbox batches, remote acknowledgements.
- `CredentialStore`: Keychain wrapper for account tokens and per-device secrets.

### 2. Product API

The app should talk to a single product API, not directly to a personal NAS or raw CodeArXiv development server.

Responsibilities:

- User login and token refresh.
- Device registration and revocation.
- Library metadata sync.
- CodeArXiv feed access and preferences.
- Optional encrypted file backup metadata.
- Per-user rate limits, audit logs, and ownership checks.

Recommended runtime:

- API service behind HTTPS.
- PostgreSQL for user, sync, and metadata tables.
- Object storage for optional uploaded encrypted PDFs and cached public arXiv assets.
- Background workers for feed ingestion, thumbnail generation, recommendation vectors, and bulk prefetch jobs.
- EdgeOne or another edge/proxy layer in front of the API for TLS termination, WAF, DDoS mitigation, caching public assets, and hiding origins.

### 3. CodeArXiv Feed Service

CodeArXiv remains the recommendation/feed engine, but Paper Codex should consume it through the product API.

Responsibilities:

- Daily arXiv ingestion.
- Feed enrichment: titles, summaries, authors, categories, tags, links, thumbnail assets, similarity scores.
- User preference application: category filters, tag whitelist/blacklist, similarity folders.
- Public arXiv asset/PDF prefetch jobs.

Paper Codex should not require the user to know a CodeArXiv token or raw CodeArXiv URL. The app should authenticate to the product API; the product API can call CodeArXiv internally.

### 4. File And Cache Layer

Paper Codex should make file state explicit.

File states:

- `saved_local`: user saved paper, stored in durable library path.
- `cache_preview`: opened from Discover but not saved, disposable.
- `feed_pdf_cache`: bulk cached PDF for a daily arXiv feed, disposable by policy but reusable if the user saves that paper.
- `remote_public`: public arXiv PDF known by URL or arXiv ID, not stored locally.
- `remote_private_encrypted`: optional user-uploaded PDF backup encrypted before or during upload.
- `missing_local`: metadata exists but local PDF is unavailable.

Cache policy:

- Metadata feed cache is small and retained by date until the user clears it.
- Small thumbnails are retained by date and can be regenerated by downloading feed assets.
- Large preview images are retained under a size budget.
- Feed PDF cache is opt-in per date/date range and has a separate size budget.
- Saved library PDFs are never deleted by cache cleanup.

## Local Schema V2

The current schema should evolve rather than be patched with ad hoc columns.

### Accounts And Devices

`local_accounts`

- `id`
- `remote_user_id`
- `display_name`
- `email`
- `sync_enabled`
- `last_login_at`
- `created_at`
- `updated_at`

`devices`

- `id`
- `remote_device_id`
- `name`
- `public_key`
- `created_at`
- `revoked_at`

### Papers And Files

`papers`

- `id`
- `canonical_key`
- `title`
- `authors_json`
- `year`
- `abstract`
- `source_kind`
- `source_url`
- `arxiv_id`
- `arxiv_id_versioned`
- `doi`
- `is_saved`
- `created_at`
- `updated_at`
- `deleted_at`
- `sync_revision`

`paper_files`

- `id`
- `paper_id`
- `storage_state`
- `local_path`
- `content_hash`
- `byte_count`
- `mime_type`
- `remote_file_id`
- `encryption_state`
- `created_at`
- `updated_at`

`paper_sources`

- `id`
- `paper_id`
- `source_type`
- `source_id`
- `url`
- `version`
- `metadata_json`
- `created_at`

### Organization

`folders`

- `id`
- `parent_id`
- `name`
- `sort_order`
- `deleted_at`
- `sync_revision`

`paper_folders`

- `paper_id`
- `folder_id`
- `created_at`
- `deleted_at`

`tags`

- `id`
- `parent_id`
- `name`
- `color`
- `sort_order`
- `deleted_at`
- `sync_revision`

`paper_tags`

- `paper_id`
- `tag_id`
- `created_at`
- `deleted_at`

Use folders for library navigation and hierarchical tags for facets. Existing categories migrate to folders; existing flat tags migrate to root-level tags.

### Notes, Anchors, And Annotations

`paper_notes`

- `id`
- `paper_id`
- `anchor_id`
- `title`
- `body_markdown`
- `created_at`
- `updated_at`
- `deleted_at`
- `sync_revision`

`pdf_annotations`

- `id`
- `paper_id`
- `anchor_id`
- `page`
- `kind`
- `color`
- `text`
- `bbox_list_json`
- `created_at`
- `updated_at`
- `deleted_at`
- `sync_revision`

Existing `anchors`, `spans`, and `pages` stay local-first but get `updated_at`, `deleted_at`, and `sync_revision` where user-authored content needs sync. Extracted page text and spans can remain local-only until a user explicitly opts into cloud indexing.

### arXiv Cache

`arxiv_feed_dates`

- `date`
- `source`
- `feed_version`
- `filter_snapshot_json`
- `cached_at`
- `expires_at`

`arxiv_feed_items`

- `date`
- `arxiv_id`
- `paper_json`
- `sort_key`
- `similarity`
- `is_favorite`
- `cached_at`

`arxiv_assets`

- `asset_key`
- `arxiv_id`
- `date`
- `kind`
- `local_path`
- `url`
- `content_hash`
- `byte_count`
- `cached_at`
- `last_accessed_at`

`arxiv_pdf_cache`

- `arxiv_id`
- `date`
- `local_path`
- `content_hash`
- `byte_count`
- `cached_at`
- `last_accessed_at`
- `promoted_paper_id`

### Sync State

`sync_entities`

- `entity_type`
- `entity_id`
- `local_revision`
- `remote_revision`
- `dirty`
- `deleted`
- `last_synced_at`

`sync_outbox`

- `id`
- `entity_type`
- `entity_id`
- `operation`
- `payload_json`
- `base_remote_revision`
- `created_at`
- `attempt_count`
- `last_error`

`sync_cursors`

- `scope`
- `cursor`
- `updated_at`

## Sync Protocol

The sync protocol should be simple, idempotent, and conflict-aware.

### Login

Use a browser-based OAuth/PKCE flow or a device-code flow. The app receives an access token and refresh token from the product API. Access tokens are short-lived. Refresh tokens are rotatable and stored in Keychain.

Local-only users can skip login. If the user signs in after building a local library, the app links the existing local database to the remote account only after explicit confirmation.

### Push

The app sends batches from `sync_outbox`.

Each change includes:

- `entity_type`
- `entity_id`
- `operation`
- `payload`
- `base_remote_revision`
- `client_change_id`
- `device_id`

The server applies idempotency by `client_change_id`. Ownership is derived from auth, not from payload.

### Pull

The app pulls changes with a server cursor.

The server returns:

- `changes`
- `next_cursor`
- `server_time`

The app applies changes in a local transaction and updates `sync_cursors` only after the transaction succeeds.

### Conflict Rules

- Paper identity merges by canonical keys: arXiv ID, DOI, source URL, and file hash.
- Folders and tags use entity-level revisions. Rename conflicts use last-write-wins with preserved history in audit logs.
- Paper-tag and paper-folder membership use add/remove tombstones so concurrent adds and removes are deterministic.
- Notes are independent entities; edits conflict only on the same note.
- Anchor/annotation edits are independent entities; deletion uses tombstones.
- Folder/tag tree conflicts cannot silently corrupt hierarchy. If a parent is deleted remotely while a child is edited locally, reparent the child to a `Sync Conflicts` folder/tag and surface it in Settings.

## Backend Schema

The product API should store syncable metadata in relational tables.

Core tables:

- `users`
- `devices`
- `refresh_tokens`
- `papers`
- `paper_sources`
- `library_items`
- `folders`
- `tags`
- `paper_folders`
- `paper_tags`
- `paper_notes`
- `anchors`
- `pdf_annotations`
- `sync_events`
- `sync_cursors`
- `arxiv_feed_preferences`
- `arxiv_favorites`
- `file_objects`
- `audit_events`

The backend should not store raw local absolute paths. It stores file object IDs and metadata. Each row has `user_id`, `created_at`, `updated_at`, `deleted_at`, and a revision field.

## PDF Sync Strategy

Default behavior:

- Public arXiv PDFs are not uploaded by the app. The backend stores arXiv ID and canonical URL. Other devices can redownload the public PDF and verify hash when needed.
- User-imported private PDFs stay local by default.
- Metadata, tags, notes, anchors, and sessions sync online.

Optional backup behavior:

- A user can enable encrypted PDF backup.
- Each file is encrypted with a per-file data key.
- File data keys are wrapped for the user's active devices.
- The server stores ciphertext and wrapped keys, not plaintext private PDFs.
- The first synced release ships metadata sync only. Encrypted private PDF backup belongs to Phase 5 after metadata sync is stable.

## Daily arXiv Offline Behavior

Settings should expose cache policies:

- Cache daily metadata automatically for the latest N days.
- Cache small thumbnails automatically.
- Cache large previews on demand or for saved/favorited papers.
- Cache all PDFs for a selected date/date range.
- Keep feed PDF cache under a configurable size budget.
- Clear disposable arXiv cache without touching saved library PDFs.

The app should show per-date cache state:

- metadata cached
- thumbnails cached
- large previews cached
- PDFs cached count / total count

When the user saves a paper that already exists in `arxiv_pdf_cache`, the app moves or hard-links the cached PDF into the durable library path and records `promoted_paper_id`.

## Security Design

### What EdgeOne Or A Similar Edge Layer Solves

An edge/proxy layer can:

- Hide direct origin addresses.
- Terminate TLS.
- Provide WAF and DDoS protection.
- Rate-limit abusive clients.
- Cache public feed assets.
- Route traffic to healthy origins.

It does not by itself ensure data safety. Data safety still requires application-level authentication, authorization, encryption, audit logging, and careful client storage.

### Required Security Controls

- HTTPS only in release builds.
- HSTS at the product domain.
- No bearer tokens in `UserDefaults`; use Keychain.
- No shared long-lived API token in the app bundle.
- Short-lived access tokens and refresh-token rotation.
- Device registration and token revocation.
- Ownership checks on every endpoint.
- Object-level authorization tests for every sync entity.
- Request-size and file-size limits.
- Per-user and per-device rate limits.
- Audit log for login, device registration, sync writes, file backup, and destructive operations.
- Sensitive fields excluded from analytics and logs.
- Auth headers attached only to first-party API origin.
- Vendored MathJax or local renderer for offline/private builds.
- Development endpoints and ATS exceptions excluded from release configuration.

The design should be checked against OWASP API Security Top 10 2023 risks, especially object-level authorization, authentication, authorization for property-level writes, unrestricted resource consumption, unsafe third-party API consumption, and security misconfiguration.

## Migration Plan

### Phase 1: Local Store V2

- Add the new schema alongside current tables.
- Migrate current `categories` to `folders`.
- Migrate current flat `tags` to root-level hierarchical `tags`.
- Migrate `papers` into V2 paper/file/source rows.
- Preserve current IDs where possible.
- Keep current app behavior unchanged after migration.

### Phase 2: Secure Connection Settings

- Move product API credentials to Keychain.
- Remove release HTTP defaults and ATS exceptions.
- Add a product API environment profile: development, staging, production.
- Restrict Authorization headers to the product API origin.

### Phase 3: arXiv Import And Offline Cache

- Add robust arXiv ID/link extraction in the local app.
- Add daily metadata/thumb/full-image/PDF cache policies.
- Add per-date cache status and background prefetch jobs.
- Promote cached PDFs into saved library paths without duplicate downloads.

### Phase 4: User Login And Metadata Sync

- Add login and device registration.
- Implement sync outbox/pull cursor.
- Sync papers, folders, tags, memberships, notes, anchors, annotations, and preferences.
- Add conflict handling and a small Settings view for sync health/conflicts.

### Phase 5: Optional Encrypted File Backup

- Add encrypted PDF backup only after metadata sync is stable.
- Do not block core reading and library sync on private PDF upload.

## Verification

Local checks:

- Migration preserves current library, tags, categories, sessions, and cached arXiv papers.
- Offline launch works with network disabled.
- Cached daily feed opens without network.
- Cached feed PDF promotes into saved library without redownloading.
- Local-only mode works without account data.
- Keychain credentials survive relaunch and are not present in `UserDefaults`.

Sync checks:

- Push is idempotent.
- Pull cursor updates only after transaction success.
- Offline edits sync after reconnect.
- Concurrent tag membership changes merge deterministically.
- Folder/tag tree conflicts do not corrupt hierarchy.
- Deleting one entity on another device creates a tombstone and preserves recoverable local state until sync is acknowledged.

Backend checks:

- Invalid, expired, and revoked tokens are rejected.
- User A cannot read or modify User B objects by changing IDs.
- Sync payloads cannot change protected fields such as `user_id`, `owner_id`, `remote_revision`, or server timestamps.
- File upload/download is size-limited and ownership-checked.
- Origin is not directly exposed as a public development server.

UI checks:

- Settings shows login state, sync state, cache state, and conflicts.
- Library still works offline.
- Discover shows cached date state.
- Bulk PDF cache has visible progress and cancellation.
- Error copy distinguishes auth failure, offline mode, cache miss, and remote service failure.

## Open Decisions

1. Private PDF cloud backup should remain opt-in and encrypted. The first synced release can ship metadata sync only.
2. CodeArXiv should become an internal feed/recommendation service behind the product API. The app should stop exposing raw CodeArXiv base URL/token to normal users.
3. Library notes should be paper-level first; span/anchor-attached notes can build on the same table.
4. Full-text extracted spans should remain local-only until there is a clear need and explicit user consent to sync them.
5. Release builds should vendor or localize MathJax rather than relying on a public CDN.

## External References

- OWASP API Security Top 10 2023: https://owasp.org/API-Security/editions/2023/en/0x11-t10/
- Apple App Transport Security: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity
- Apple Keychain Services: https://developer.apple.com/documentation/security/keychain_services/keychain_items/using_the_keychain_to_manage_user_secrets
- Tencent Cloud EdgeOne overview: https://www.tencentcloud.com/document/product/1145/47614
