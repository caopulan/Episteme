# Local Discover Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the local-first Discover engine: arXiv range search, keyword/category filters, optional local similarity ranking, cached raw/enriched metadata, manual processing queue, and removal of runtime CodeArXiv client concepts.

**Architecture:** Keep arXiv networking, range/query models, cache, enrichment records, and ranking in `PaperCodexCore`; keep UI orchestration and Codex processing in `PaperCodexApp.AppModel`; make `DiscoverView` a search/rank/process workspace. Use JSON file caches under Application Support for query/enrichment state, while preserving existing SQLite library behavior.

**Tech Stack:** Swift 6, SwiftUI, Foundation URLSession/XMLParser, local JSON caches, existing Codex CLI integration, existing core check executable, Computer Use for app smoke tests.

---

### Task 1: Core Discover Range And Cache Models

**Files:**
- Create: `Sources/PaperCodexCore/LocalDiscoverEngine.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Write failing tests**

Add `runLocalDiscoverEngineChecks()` to `Sources/PaperCodexCoreChecks/main.swift`:

```swift
func runLocalDiscoverEngineChecks() throws {
    let range = try DiscoverDateRange(start: "2026-04-27", end: "2026-04-29")
    try check(range.dates == ["2026-04-27", "2026-04-28", "2026-04-29"], "discover date range should expand inclusive dates")

    let queryA = DiscoverQuery(
        keyword: "diffusion policy",
        dateRange: range,
        categories: ["cs.CV", "cs.AI"],
        similaritySourceIDs: ["tag-robot", "cat-vision"],
        rankingVersion: "rank-v1"
    )
    let queryB = DiscoverQuery(
        keyword: "  diffusion   policy ",
        dateRange: range,
        categories: ["cs.AI", "cs.CV", "cs.AI"],
        similaritySourceIDs: ["cat-vision", "tag-robot", "tag-robot"],
        rankingVersion: "rank-v1"
    )
    try check(queryA.normalized == queryB.normalized, "discover query normalization should ignore whitespace and duplicate order")
    try check(queryA.cacheKey == queryB.cacheKey, "discover query cache key should be stable for equivalent queries")

    let enrichment = DiscoverPaperEnrichment(
        arxivID: "2604.18803",
        processorVersion: DiscoverPaperEnrichment.currentProcessorVersion,
        promptVersion: DiscoverPaperEnrichment.currentPromptVersion,
        modelIdentity: "codex",
        titleZH: "本地论文阅读器",
        summaryZH: "提出一个本地优先的论文发现和阅读流程。",
        contribution: "把 arXiv 检索、缓存和阅读工作流连接起来。",
        tags: ["paper-reader", "local-first"],
        links: ["github": "https://github.com/example/paper-reader"],
        generatedAt: Date(timeIntervalSince1970: 1_777_300_000),
        error: nil
    )
    try check(enrichment.isCurrent, "fresh enrichment should be current")

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-discover-engine-\(UUID().uuidString)", isDirectory: true)
    let cache = LocalDiscoverCache(root: tempRoot)
    try cache.saveQueryResult(
        DiscoverQueryResult(query: queryA.normalized, arxivIDs: ["2604.18803"], generatedAt: enrichment.generatedAt)
    )
    try cache.saveEnrichment(enrichment)
    try check(try cache.loadQueryResult(cacheKey: queryA.cacheKey)?.arxivIDs == ["2604.18803"], "discover query cache should round-trip ordered ids")
    try check(try cache.loadEnrichment(arxivID: "2604.18803")?.titleZH == "本地论文阅读器", "discover enrichment cache should round-trip processed metadata")
}
```

Call it from the bottom dispatcher:

```swift
if selectedChecks.isEmpty || selectedChecks.contains("local-discover-engine") {
    try runLocalDiscoverEngineChecks()
    print("local-discover-engine: pass")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run PaperCodexCoreChecks local-discover-engine`

Expected: compile failure because `DiscoverDateRange`, `DiscoverQuery`, `DiscoverPaperEnrichment`, `DiscoverQueryResult`, and `LocalDiscoverCache` do not exist.

- [ ] **Step 3: Implement core models and cache**

Create `Sources/PaperCodexCore/LocalDiscoverEngine.swift` with:

```swift
import CryptoKit
import Foundation

public struct DiscoverDateRange: Codable, Equatable, Sendable {
    public var start: String
    public var end: String
    public init(start: String, end: String) throws
    public var dates: [String] { get }
}

public struct DiscoverQuery: Codable, Equatable, Sendable {
    public var keyword: String
    public var dateRange: DiscoverDateRange
    public var categories: [String]
    public var similaritySourceIDs: [String]
    public var rankingVersion: String
    public var normalized: DiscoverQuery { get }
    public var cacheKey: String { get }
}

public struct DiscoverQueryResult: Codable, Equatable, Sendable {
    public var query: DiscoverQuery
    public var arxivIDs: [String]
    public var generatedAt: Date
}

public struct DiscoverPaperEnrichment: Codable, Equatable, Sendable {
    public static let currentProcessorVersion = "local-discover-enrichment-v1"
    public static let currentPromptVersion = "discover-metadata-zh-v1"
    public var arxivID: String
    public var processorVersion: String
    public var promptVersion: String
    public var modelIdentity: String
    public var titleZH: String
    public var summaryZH: String
    public var contribution: String
    public var tags: [String]
    public var links: [String: String]
    public var generatedAt: Date
    public var error: String?
    public var isCurrent: Bool { get }
}

public final class LocalDiscoverCache {
    public init(root: URL, fileManager: FileManager = .default)
    public func saveQueryResult(_ result: DiscoverQueryResult) throws
    public func loadQueryResult(cacheKey: String) throws -> DiscoverQueryResult?
    public func saveEnrichment(_ enrichment: DiscoverPaperEnrichment) throws
    public func loadEnrichment(arxivID: String) throws -> DiscoverPaperEnrichment?
}
```

Use ISO `yyyy-MM-dd` parsing for ranges, SHA256 over canonical JSON for query keys, and safe filename components for arXiv IDs.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run PaperCodexCoreChecks local-discover-engine`

Expected: `local-discover-engine: pass`

- [ ] **Step 5: Commit**

```bash
git add Sources/PaperCodexCore/LocalDiscoverEngine.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add local discover cache models"
```

### Task 2: Direct arXiv Range Fetching And CodeArXiv Cleanup

**Files:**
- Modify: `Sources/PaperCodexCore/LocalArxivClient.swift`
- Modify: `Sources/PaperCodexCore/ArxivFeed.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`
- Modify: `Sources/PaperCodexApp/AppModel.swift`

- [ ] **Step 1: Write failing tests**

Extend `runLocalArxivClientChecks()`:

```swift
let multiDateHTML = """
<html><body>
<h3>Wed, 29 Apr 2026 (showing first 2 of 2 entries)</h3>
<dl>
  <dt><a href="/abs/2604.20002">arXiv:2604.20002</a></dt>
  <dt><a href="/abs/2604.20001v2">arXiv:2604.20001v2</a></dt>
</dl>
<h3>Tue, 28 Apr 2026 (showing first 1 of 1 entries)</h3>
<dl>
  <dt><a href="/abs/2604.19999">arXiv:2604.19999</a></dt>
</dl>
</body></html>
"""
let listPages = try LocalArxivClient.parseListPages(multiDateHTML)
try check(listPages.map(\.date) == ["2026-04-29", "2026-04-28"], "local arXiv parser should parse every date section")
try check(listPages[0].ids == ["2604.20002", "2604.20001"], "local arXiv parser should dedupe versioned ids per section")
try check(listPages[1].ids == ["2604.19999"], "local arXiv parser should parse ids in later sections")
```

Update `runArxivFeedChecks()` sample to remove `filters`, `favorites`, and `user`, and assert `ArxivFeedResponse` no longer exposes CodeArXiv fields.

Remove `runArxivLiveFeedChecks()` and its dispatcher entry.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift run PaperCodexCoreChecks local-arxiv-client
swift run PaperCodexCoreChecks arxiv-feed
```

Expected: first command fails because `parseListPages` does not exist; second fails after removing CodeArXiv assertions until model cleanup is implemented.

- [ ] **Step 3: Implement range parsing and remove CodeArXiv client**

In `LocalArxivClient`, add:

```swift
public func fetchFeed(range: DiscoverDateRange) async throws -> ArxivFeedResponse
public static func parseListPages(_ html: String) throws -> [LocalArxivListPage]
```

`fetchFeed(range:)` should fetch all configured category list pages, collect all sections whose dates are inside the range, dedupe IDs across categories, preserve `listCategoriesByID`, fetch Atom metadata in batches, and return an `ArxivFeedResponse` whose `date` is `"\(range.start)...\(range.end)"`.

In `ArxivFeed.swift`, delete:

- `CodeArxivUser`
- `CodeArxivTagFilters`
- `CodeArxivUserFilters`
- `CodeArxivFavorite`
- `CodeArxivUserState`
- `CodeArxivFilterUpdatePayload`
- `ArxivFeedClientError`
- `ArxivFeedClient`
- `ArxivFeedPaperEnvelope`

Remove `filters`, `favorites`, and `user` fields from `ArxivFeedResponse`. Update `AppModel.applyLocalDiscoverPreferences` initializer calls.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift run PaperCodexCoreChecks local-arxiv-client arxiv-feed
```

Expected: both checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaperCodexCore/LocalArxivClient.swift Sources/PaperCodexCore/ArxivFeed.swift Sources/PaperCodexCoreChecks/main.swift Sources/PaperCodexApp/AppModel.swift
git commit -m "feat: fetch arxiv ranges locally"
```

### Task 3: AppModel Search State, Query Cache, And Lightweight Processing Cache

**Files:**
- Modify: `Sources/PaperCodexApp/AppModel.swift`

- [ ] **Step 1: Add app state**

Add published state:

```swift
@Published var discoverKeyword = ""
@Published var discoverStartDate = currentISODate()
@Published var discoverEndDate = currentISODate()
@Published var discoverSelectedCategories: [String] = ["cs.CV"]
@Published var discoverSelectedSimilaritySourceIDs: [String] = []
@Published var discoverResultIDs: [String] = []
@Published var discoverEnrichmentsByID: [String: DiscoverPaperEnrichment] = [:]
@Published var isSearchingDiscover = false
@Published var isProcessingDiscoverResults = false
@Published var discoverProcessingProgress: ArxivCacheProgress?
```

Add `private let localDiscoverCache: LocalDiscoverCache`.

- [ ] **Step 2: Implement search**

Add:

```swift
func applyDiscoverQuickRange(_ preset: DiscoverQuickRange)
func searchDiscover() async
func processCurrentDiscoverResults(_ papers: [ArxivFeedPaper]) async
func discoverEnrichment(for paper: ArxivFeedPaper) -> DiscoverPaperEnrichment?
```

`searchDiscover` should build `DiscoverQuery`, fetch `LocalArxivClient.fetchFeed(range:)`, apply keyword filter, apply existing local ranking, save `DiscoverQueryResult`, load cached enrichments for visible papers, set `arxivFeed`, and set cache progress. If live fetch fails, load cached query result and cached feeds when available before surfacing the error.

`processCurrentDiscoverResults` should iterate the visible papers, skip current enrichment, generate a local deterministic first-pass enrichment from metadata, cache it, and refresh the card immediately. This first-pass processor is intentionally local and deterministic; Codex/LLM processing can replace the implementation behind the same cache contract.

- [ ] **Step 3: Run build**

Run: `swift build`

Expected: build passes.

- [ ] **Step 4: Commit**

```bash
git add Sources/PaperCodexApp/AppModel.swift
git commit -m "feat: add discover search state"
```

### Task 4: Discover Workspace UI

**Files:**
- Modify: `Sources/PaperCodexApp/DiscoverView.swift`

- [ ] **Step 1: Generate UI reference**

Use image generation for a compact macOS Discover workspace reference with: top search/range/category/similarity/process controls, left filters, responsive paper cards, progress strip, raw/processed card states.

- [ ] **Step 2: Replace single-date toolbar**

Replace `DateMenuButton` with:

- keyword field bound to `model.discoverKeyword`.
- start/end date text fields bound to `model.discoverStartDate` and `model.discoverEndDate`.
- quick buttons for This Week, This Month, Last 7 Days, Last 30 Days.
- category menu.
- Search button calling `model.searchDiscover()`.
- Process Results button calling `model.processCurrentDiscoverResults(papers)`.

- [ ] **Step 3: Update cards**

Cards should display:

- raw English title and abstract when no enrichment exists.
- Chinese title, summary, contribution, and generated tags when enrichment exists.
- clear "Unprocessed", "Cached", or "Processed" pill.
- similarity score meter if available.
- Open and Add in lower-right.

- [ ] **Step 4: Run build**

Run: `swift build`

Expected: build passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/PaperCodexApp/DiscoverView.swift
git commit -m "feat: redesign discover workspace"
```

### Task 5: Verification And Runtime Smoke

**Files:**
- No source files unless smoke test exposes a defect.

- [ ] **Step 1: Run full checks**

Run:

```bash
swift build
swift run PaperCodexCoreChecks
```

Expected: build succeeds and all core checks pass.

- [ ] **Step 2: Rebuild app bundle**

Run: `scripts/build-app-bundle.sh`

Expected: `/Users/chunqiu/Applications/PaperCodex.app`

- [ ] **Step 3: Relaunch app**

Run:

```bash
pkill -x PaperCodexApp || true
open /Users/chunqiu/Applications/PaperCodex.app
```

- [ ] **Step 4: Use Computer Use smoke test**

Verify:

- Discover opens as a search workspace.
- Quick range buttons update the visible range.
- Search loads raw arXiv cards.
- Process Results shows progress and fills processed fields.
- Open downloads a PDF and enters reader.

- [ ] **Step 5: Commit fixes if needed**

If smoke reveals defects, fix them, rerun targeted verification, and commit:

```bash
git add Sources/PaperCodexApp Sources/PaperCodexCore Sources/PaperCodexCoreChecks
git commit -m "fix: stabilize local discover workflow"
```

