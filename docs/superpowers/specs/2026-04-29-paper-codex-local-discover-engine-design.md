# Paper Codex Local Discover Engine Design

Date: 2026-04-29
Status: approved for implementation planning
Supersedes the Discover portions of:

- `docs/superpowers/specs/2026-04-28-codearxiv-discover-library-design.md`
- `docs/superpowers/specs/2026-04-29-paper-codex-local-first-arxiv-design.md`

## Goal

Discover should become a fast local paper-discovery workspace for finding new arXiv papers worth reading. It should not feel like a copied CodeArXiv daily feed. The user should be able to search arXiv by time range, primary category, keyword, and similarity to the local library; quickly skim raw metadata; then explicitly process the current result set for Chinese titles, summaries, and tags.

The page must work without a backend. arXiv is the only online source for this version. All query results, raw metadata, embeddings, translations, summaries, tags, progress state, and errors are stored locally.

## Product Shape

Discover has three workflow phases:

1. Search.
2. Rank.
3. Process.

Search fetches or loads arXiv metadata. Rank sorts the results using local rules and optional embeddings. Process performs slower enrichment such as translation, summary generation, tag suggestion, and link extraction. These phases are separate so browsing starts quickly and expensive processing never blocks the first result view.

## Search Controls

The top bar should contain:

- Keyword search.
- Date range picker with explicit start and end dates.
- Quick ranges: Today, This Week, This Month, Last 7 Days, Last 30 Days.
- Primary category selector, with common computer-science categories first.
- Similarity source selector, populated from local library folders, tags, and optionally individual saved papers.
- Search button.
- Process Results button.

The selected date range is authoritative. Quick ranges are just shortcuts that update the start and end date fields.

The first implementation should support arXiv category listing pages and Atom metadata. It should not require the historical CodeArXiv server. If arXiv cannot provide an older range from direct listing pages, the app should show cached results for that range when available and otherwise report a clear range-unavailable error.

## Result Cards

Cards should support three levels of information:

Raw:

- arXiv ID.
- primary category.
- date.
- English title.
- authors.
- English abstract preview.
- arXiv/PDF/GitHub/project links when available.

Ranked:

- similarity score if available.
- visual score meter.
- matched source label, such as "similar to Diffusion folder" or "matched tag: robot".
- whitelist, neutral, or blacklist group when local tag rules apply.

Processed:

- Chinese title.
- Chinese short summary.
- suggested tags.
- extracted code/project/Hugging Face links.
- processing status and error if enrichment failed.

Unprocessed cards must remain useful. They display original arXiv content and a visible "Unprocessed" state instead of empty Chinese text.

## Filtering

The left sidebar should become a filter panel for the current search result set:

- Categories.
- Generated/user tags.
- Processed vs unprocessed.
- In Library vs new.
- Has GitHub or project page.
- Similarity buckets: high, medium, low, none.

Filters never trigger network work by themselves. They only filter the loaded result set.

## Local Cache Model

Discover uses four local caches.

### Raw Metadata Cache

Stores arXiv metadata by normalized arXiv ID, date, primary category, and list category. It contains source data only:

- title.
- abstract.
- authors.
- categories.
- primary category.
- published and updated timestamps.
- comments.
- source links.
- fetched-at timestamp.

This cache is the source of truth for offline raw Discover browsing.

### Query Cache

Stores a query hash and the ordered list of arXiv IDs returned for that query. The hash includes:

- date range.
- categories.
- keyword.
- selected ranking mode.
- selected similarity sources.
- local ranking preference version.

The query cache makes it cheap to return to a previous discovery session.

### Embedding Cache

Stores embeddings by content hash and provider identity:

- arXiv ID or local paper ID.
- input text hash.
- provider base URL identity.
- model.
- vector.
- generated-at timestamp.
- error, if generation failed.

The default embedding input for arXiv papers is English title plus abstract. Library source vectors are computed from saved paper title, abstract when known, and extracted text snippets when available.

### Enrichment Cache

Stores manually triggered processing results:

- arXiv ID.
- processor version.
- prompt version.
- model identity.
- Chinese title.
- Chinese abstract or summary.
- short contribution summary.
- suggested tags.
- extracted links.
- generated-at timestamp.
- error, if processing failed.

The app must skip enrichment records that are already current for the active processor and prompt versions. A Force Reprocess action can be added later, but normal Process Results should avoid repeated work.

## Embedding Ranking

Embedding is optional but should be the preferred ranking path when configured.

When Search is clicked:

1. Load or fetch raw arXiv metadata for the selected range and category.
2. Filter by keyword locally across title, abstract, authors, category, and arXiv ID.
3. Build source vectors from selected local folders, tags, or papers.
4. Generate missing arXiv embeddings for result items, using the local embedding settings.
5. Compute cosine similarity between each result and the selected source vectors.
6. Rank by whitelist group, similarity score, publish date, then arXiv ID.

If embedding settings are missing or a provider call fails, Search still completes with raw results and a visible warning. Cards without vectors get a "No similarity" state.

Similarity source behavior:

- Folder source means all saved papers in the folder.
- Tag source means all saved papers carrying that tag.
- Paper source means the selected paper alone.
- Multiple sources use max similarity for display and sorting.
- The card records the best matching source label.

## Manual Processing

Process Results acts on the currently loaded and filtered result list. It should process in visible order from top to bottom.

For each paper:

1. If current enrichment exists, mark it as cached and skip.
2. Build a prompt from raw title, abstract, authors, category, comments, and known links.
3. Run the configured local processing path.
4. Parse structured JSON.
5. Save enrichment.
6. Refresh the card immediately.

The first implementation can use the existing Codex CLI integration for processing. It can later add a faster OpenAI-compatible HTTP LLM provider behind a small boundary. The UI should not assume a specific provider.

Processing output should be strict JSON with fields for Chinese title, Chinese summary, contribution summary, tags, and links. Parse failures are shown per card and do not stop the whole queue.

Processing controls:

- Process Results.
- Cancel Processing.
- Progress text: processed, cached, failed, total.
- Per-card status: queued, processing, processed, cached, failed.

## CodeArXiv Removal

The local Discover engine should remove runtime CodeArXiv concepts:

- No CodeArXiv base URL.
- No CodeArXiv token.
- No CodeArXiv username.
- No remote favorites.
- No remote user filters.
- No CodeArXiv API client.
- No CodeArXiv live test.

Useful generic data remains:

- arXiv paper model.
- arXiv links.
- local feed/raw metadata cache.
- local assets or thumbnails.
- similarity ranker.
- local tag whitelist/blacklist.

Any type still named `CodeArxiv` after this work should either be deleted or replaced by a local product name.

## UI Direction

Discover should feel dense, fast, and scannable:

- No Paper Details side panel.
- No marketing copy.
- Cards in a responsive multi-column grid.
- Search controls stay visible at the top.
- Processing progress stays near the controls.
- Hover states make buttons and cards clearly interactive.
- The image area should be optional; cards must work even when arXiv has no preview image.
- Open and Add stay in the lower-right of each card.

The default result view is raw and immediate. Processed Chinese summaries progressively appear without reshuffling the whole grid unless the active sort depends on newly available tags or embeddings.

## Error Handling

Expected failures should be explicit:

- arXiv range unavailable.
- network timeout.
- cached-only mode.
- embedding provider missing.
- embedding provider failed.
- Codex processing failed.
- JSON parse failed.
- PDF download failed.

Errors should not erase cached results. The user should keep browsing whatever data is available locally.

## Testing

Core checks should cover:

- parsing multiple date sections from arXiv listing HTML.
- building date ranges and quick ranges.
- merging multiple categories across a range.
- query hashing stability.
- raw metadata cache round trip.
- enrichment cache skip behavior.
- embedding cache key behavior.
- ranking with multiple similarity sources.
- deletion of CodeArXiv-only model/client tests.

App smoke tests should cover:

- selecting a range.
- running Search.
- seeing raw cards immediately.
- running Process Results.
- seeing progress advance and processed fields appear.
- reopening the app and loading cached query/results.
- opening a paper into the reader.
- saving a paper with selected tags.

