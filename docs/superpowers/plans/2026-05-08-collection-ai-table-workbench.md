# Collection AI Table Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recompose Collections into a C1-B AI table workbench with a main spreadsheet pane and one docked, selection-first right panel.

**Architecture:** Keep the existing JSON-backed collection model and current table editing logic. Reorganize `CollectionView.swift` so `CollectionWorkbench` owns a compact table surface and a new `CollectionAIDock` owns `Selection`, `Field`, `Chat`, and `Runs` tabs. Extend collection chat prompt creation with a bounded selection-context string so dock actions can send table-aware prompts without widening the persistence model.

**Tech Stack:** Swift, SwiftUI, `PaperCodexCore`, existing `AppModel` collection APIs, `PaperCodexCoreChecks`, `scripts/build-app-bundle.sh`.

---

## File Structure

- Modify `Sources/PaperCodexApp/CollectionView.swift`
  - Remove the separate `CollectionChatPanel` from `contentPane`.
  - Add `CollectionAIDock`, `CollectionAIDockTab`, `CollectionSelectionPanel`, `CollectionFieldPanel`, `CollectionRunsPanel`, and compact supporting views.
  - Reuse current grid, formula bar, validation, and field-setting logic.
  - Move the existing collection chat UI into the `Chat` tab.
- Modify `Sources/PaperCodexApp/AppModel.swift`
  - Add optional bounded selection context to collection chat prompt construction.
  - Keep current call sites compatible through a default parameter.
- Modify `Sources/PaperCodexCoreChecks/main.swift`
  - Add source checks for the C1-B layout, integrated dock tabs, field inspector relocation, runs panel, and selection-context prompt.
- Modify `docs/superpowers/specs/2026-05-07-collection-ai-table-workbench-redesign.md`
  - Mark status as approved for implementation planning.

## Task 1: Source Checks For C1-B Workbench

**Files:**
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add failing source checks**

In `runUILayoutSourceChecks()`, after the existing collection workbench checks, add checks shaped like this:

```swift
try check(
    collectionSource.contains("CollectionAIDock")
        && collectionSource.contains("enum CollectionAIDockTab")
        && collectionSource.contains("CollectionSelectionPanel")
        && collectionSource.contains("CollectionFieldPanel")
        && collectionSource.contains("CollectionRunsPanel"),
    "CollectionView should use a docked selection-first AI panel"
)
try check(
    collectionSource.contains("CollectionChatPanel(")
        && collectionSource.contains("tab: .chat")
        && !collectionSource.contains("CollectionChatPanel(collection: collection)\\n                    .frame(width: 380)"),
    "Collection chat should live inside the integrated dock instead of a separate right panel"
)
try check(
    collectionSource.contains("CollectionFieldPanel")
        && !collectionSource.contains("CollectionFieldInspector("),
    "Collection field settings should move into the dock Field tab"
)
try check(
    appModelSource.contains("selectionContext:")
        && appModelSource.contains("[Collection Selection Context]"),
    "Collection chat prompts should support bounded selection context"
)
```

- [ ] **Step 2: Verify the checks fail**

Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
```

Expected: failure on the new C1-B dock checks.

- [ ] **Step 3: Commit only if this task is split from implementation**

Do not commit this red-only state if implementing inline. Carry it into Task 2 and commit once it passes.

## Task 2: Recompose Layout Into Main Table Pane Plus Integrated Dock

**Files:**
- Modify: `Sources/PaperCodexApp/CollectionView.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add dock tab state**

In `CollectionView`, add:

```swift
@State private var activeDockTab: CollectionAIDockTab = .selection
@State private var isAIDockCollapsed = false
```

Reset them on selected collection change:

```swift
activeDockTab = .selection
isAIDockCollapsed = false
```

- [ ] **Step 2: Replace the separate chat panel in `contentPane`**

Change the selected-collection branch from:

```swift
HStack(spacing: 0) {
    tablePane(collection)
    Divider()
    CollectionChatPanel(collection: collection)
        .frame(width: 380)
}
```

to:

```swift
tablePane(collection)
```

`CollectionWorkbench` will own both the table pane and the integrated dock.

- [ ] **Step 3: Add `CollectionAIDockTab`**

Near `CollectionTableViewMode`, add:

```swift
private enum CollectionAIDockTab: String, CaseIterable, Identifiable {
    case selection
    case field
    case chat
    case runs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: "Selection"
        case .field: "Field"
        case .chat: "Chat"
        case .runs: "Runs"
        }
    }

    var systemImage: String {
        switch self {
        case .selection: "scope"
        case .field: "slider.horizontal.3"
        case .chat: "text.bubble"
        case .runs: "bolt.horizontal"
        }
    }
}
```

- [ ] **Step 4: Update `CollectionWorkbench` parameters**

Add bindings and callbacks:

```swift
@Binding var activeDockTab: CollectionAIDockTab
@Binding var isAIDockCollapsed: Bool
var activeRun: ActiveCodexRun?
var isSending: Bool
var onCancelRun: () -> Void
var onSendChatMessage: (String, String?) -> Void
var selectionContext: String?
```

Pass these from `tablePane(_:)` using existing model helpers:

```swift
activeRun: model.activeCodexRun(forCollectionID: collection.id),
isSending: model.isCollectionSending(collection.id),
onCancelRun: { model.cancelCollectionCodexRun(collection.id) },
onSendChatMessage: { message, selectionContext in
    Task {
        await model.sendCollectionMessage(message, collectionID: collection.id, selectionContext: selectionContext)
    }
}
```

- [ ] **Step 5: Recompose `CollectionWorkbench.body`**

Replace the inner `HStack` that currently places `CollectionSpreadsheet` next to `CollectionFieldInspector` with a two-pane layout:

```swift
HStack(spacing: 0) {
    VStack(spacing: 0) {
        CollectionWorkbenchHeader(...)
        Divider()
        toolbar
        CollectionViewTabs(...)
        Divider()
        CollectionFormulaBar(...)
        Divider()
        CollectionSpreadsheet(...)
        Divider()
        CollectionStatusBar(...)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)

    if !isAIDockCollapsed {
        Divider()
        CollectionAIDock(...)
            .frame(width: 340)
    } else {
        Divider()
        CollectionAIDockRail(activeDockTab: $activeDockTab, isCollapsed: $isAIDockCollapsed)
            .frame(width: 44)
    }
}
```

The table pane remains the wide side. The dock is one side panel.

- [ ] **Step 6: Run checks and commit**

Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
swift build
git diff --check
```

Expected: `ui-layout-source: pass`, build complete, no diff-check output.

Commit:

```bash
git add Sources/PaperCodexApp/CollectionView.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add collection AI dock shell"
```

## Task 3: Selection And Field Tabs

**Files:**
- Modify: `Sources/PaperCodexApp/CollectionView.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Build `CollectionAIDock` tab shell**

Create:

```swift
private struct CollectionAIDock: View {
    var collection: PaperCollectionDocument
    var selectedCell: CollectionCellCoordinate?
    var selectedRowIDs: Set<String>
    var visibleColumnCount: Int
    var columns: [PaperCollectionColumn]
    var rows: [PaperCollectionRow]
    var validationIssues: [PaperCollectionValidationIssue]
    @Binding var activeDockTab: CollectionAIDockTab
    @Binding var isCollapsed: Bool
    var activeRun: ActiveCodexRun?
    var isSending: Bool
    var onCancelRun: () -> Void
    var onSendChatMessage: (String, String?) -> Void
    var selectionContext: String?
    var onUpdateColumnTitle: (String, String) -> Void
    var onSetColumnHidden: (String, Bool) -> Void
    var onUpdateColumnWidth: (String, Double) -> Void
    var onSetColumnRequired: (String, Bool) -> Void
    var onSetColumnAllowedValues: (String, [String]) -> Void
    var onSetColumnDescription: (String, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            dockHeader
            Divider()
            tabBody
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
```

Use a segmented or icon tab header with `Selection`, `Field`, `Chat`, and `Runs`.

- [ ] **Step 2: Implement `CollectionSelectionPanel`**

Create a selection-first panel that shows:

```swift
private struct CollectionSelectionPanel: View {
    var collection: PaperCollectionDocument
    var selectedCell: CollectionCellCoordinate?
    var selectedRowIDs: Set<String>
    var columns: [PaperCollectionColumn]
    var validationIssues: [PaperCollectionValidationIssue]
    var onSendChatMessage: (String, String?) -> Void
    var selectionContext: String?
}
```

Required body behavior:

- If a cell is selected, show coordinate, field title/type, paper title, current value, and cell validation issues.
- If no cell but selected rows exist, show selected row count and actions.
- If neither, show collection summary and next actions.
- Include action buttons:

```swift
selectionAction("Explain", "Explain the selected table value and why it matters.")
selectionAction("Cite", "Find or cite supporting evidence for the selected value.")
selectionAction("Fill Field", "Fill this field for the selected or visible rows using the paper context.")
selectionAction("Validate", "Validate this selection and explain any issues.")
```

Each action calls:

```swift
onSendChatMessage(prompt, selectionContext)
```

- [ ] **Step 3: Rename and adapt the inspector into `CollectionFieldPanel`**

Rename `CollectionFieldInspector` to `CollectionFieldPanel`.

Keep existing draft ownership behavior:

```swift
@State private var draftColumnID: String?
```

Keep the last-visible-column guard:

```swift
.disabled(!column.isHidden && visibleColumnCount <= 1)
```

The panel is selected-field-driven and lives only in the dock `Field` tab.

- [ ] **Step 4: Run checks and commit**

Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
swift build
git diff --check
```

Expected: source checks pass, build complete, no diff-check output.

Commit:

```bash
git add Sources/PaperCodexApp/CollectionView.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add selection-first collection panel"
```

## Task 4: Chat And Runs Tabs

**Files:**
- Modify: `Sources/PaperCodexApp/CollectionView.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Adapt `CollectionChatPanel` for dock use**

Change `CollectionChatPanel` to accept:

```swift
var selectionContext: String?
var onSendMessage: (String, String?) -> Void
var onCancelRun: () -> Void
```

The `send()` method becomes:

```swift
private func send() {
    let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty, !isSending else {
        return
    }
    draft = ""
    onSendMessage(message, selectionContext)
}
```

The stop button calls `onCancelRun()`.

- [ ] **Step 2: Make chat scope visible**

Above the composer, add a compact scope line:

```swift
if selectionContext != nil {
    Label("Scoped to current selection", systemImage: "scope")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 3: Implement `CollectionRunsPanel`**

Create:

```swift
private struct CollectionRunsPanel: View {
    var activeRun: ActiveCodexRun?
    var isSending: Bool
    var onCancelRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Runs", systemImage: "bolt.horizontal")
                .font(.paperCodexSystem(size: 14, weight: .semibold))
            if let activeRun {
                CollectionRunBubble(run: activeRun)
                Button(role: .destructive, action: onCancelRun) {
                    Label("Stop Run", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            } else {
                ContentUnavailableView(
                    "No Active Run",
                    systemImage: "bolt.horizontal",
                    description: Text("Batch fill, validation, and table updates will appear here while Codex is running.")
                )
            }
        }
        .padding(14)
    }
}
```

- [ ] **Step 4: Wire `Chat` and `Runs` tabs in `CollectionAIDock`**

In `tabBody`:

```swift
case .chat:
    CollectionChatPanel(
        collection: collection,
        selectionContext: selectionContext,
        onSendMessage: onSendChatMessage,
        onCancelRun: onCancelRun
    )
case .runs:
    CollectionRunsPanel(
        activeRun: activeRun,
        isSending: isSending,
        onCancelRun: onCancelRun
    )
```

- [ ] **Step 5: Run checks and commit**

Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
swift build
git diff --check
```

Expected: source checks pass, build complete, no diff-check output.

Commit:

```bash
git add Sources/PaperCodexApp/CollectionView.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: move collection chat into AI dock"
```

## Task 5: Selection Context In Collection Prompts

**Files:**
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Modify: `Sources/PaperCodexApp/CollectionView.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] **Step 1: Add optional selection context to AppModel APIs**

Change:

```swift
func sendCollectionMessage(_ text: String, collectionID: String) async
```

to:

```swift
func sendCollectionMessage(_ text: String, collectionID: String, selectionContext: String? = nil) async
```

Change the private prompt helper signature to:

```swift
private func collectionPrompt(
    userMessage: String,
    collection: PaperCollectionDocument,
    papers: [Paper],
    workspacePath: String,
    selectionContext: String?
) -> String
```

When building the prompt, append:

```swift
let selectionSection = selectionContext.map { context in
    """

    [Collection Selection Context]
    \(context)
    """
} ?? ""
```

Place `\(selectionSection)` after `[Collection Columns]`.

- [ ] **Step 2: Build a bounded selection context in `CollectionView`**

Add a helper:

```swift
private func selectionPromptContext(
    collection: PaperCollectionDocument,
    visibleColumns: [PaperCollectionColumn],
    validationIssues: [PaperCollectionValidationIssue]
) -> String? {
    var lines: [String] = []
    if let selectedCell,
       let row = collection.rows.first(where: { $0.id == selectedCell.rowID }),
       let column = collection.columns.first(where: { $0.id == selectedCell.columnID }) {
        lines.append("selected_cell: \(cellCoordinateLabel(selectedCell, collection: collection))")
        lines.append("row_id: \(row.id)")
        lines.append("paper_id: \(row.paperID)")
        lines.append("paper_title: \(row.values["paper_title", default: ""])")
        lines.append("field_id: \(column.id)")
        lines.append("field_title: \(column.title)")
        lines.append("field_type: \(column.valueKind.rawValue)")
        lines.append("value: \(row.values[column.id, default: ""])")
        let issueMessages = validationIssues
            .filter { $0.rowID == row.id && $0.columnID == column.id }
            .prefix(3)
            .map(\.message)
        if !issueMessages.isEmpty {
            lines.append("validation_issues: \(issueMessages.joined(separator: " | "))")
        }
    }
    if !selectedRowIDs.isEmpty {
        lines.append("selected_row_ids: \(Array(selectedRowIDs).prefix(20).joined(separator: ", "))")
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
}
```

Add `cellCoordinateLabel` if needed:

```swift
private func cellCoordinateLabel(_ cell: CollectionCellCoordinate, collection: PaperCollectionDocument) -> String
```

- [ ] **Step 3: Pass selection context into the dock**

In `tablePane`, compute:

```swift
let selectionContext = selectionPromptContext(
    collection: collection,
    visibleColumns: visibleColumns,
    validationIssues: validationIssues
)
```

Pass it to `CollectionWorkbench`, then `CollectionAIDock`, then chat/actions.

- [ ] **Step 4: Add source checks**

Add checks:

```swift
try check(
    collectionSource.contains("selectionPromptContext(")
        && collectionSource.contains("selected_cell:")
        && collectionSource.contains("selected_row_ids:"),
    "CollectionView should build bounded selection context for AI dock actions"
)
try check(
    appModelSource.contains("selectionContext: String? = nil")
        && appModelSource.contains("[Collection Selection Context]"),
    "AppModel collection chat prompts should include optional selection context"
)
```

- [ ] **Step 5: Run checks and commit**

Run:

```bash
swift run PaperCodexCoreChecks collections collection-sources ui-layout-source
swift build
git diff --check
```

Expected: checks pass, build complete, no diff-check output.

Commit:

```bash
git add Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexApp/CollectionView.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add collection selection context prompts"
```

## Task 6: Final Verification, Bundle Rebuild, Relaunch

**Files:**
- Modify only if verification finds a concrete gap.

- [ ] **Step 1: Run automated checks**

Run:

```bash
swift run PaperCodexCoreChecks models repository citations anchors prompt workspace pdf codex codex-recovery paths fixture watch collections collection-sources ui-layout-source
swift build
git diff --check
```

Expected:

- every listed suite prints `pass`.
- `swift build` prints `Build complete`.
- `git diff --check` prints no output.

- [ ] **Step 2: Rebuild installed app bundle**

Run:

```bash
scripts/build-app-bundle.sh
```

Expected:

- `/Users/chunqiu/Applications/PaperCodex.app` is printed.
- codesign reports valid on disk and satisfies designated requirement.

- [ ] **Step 3: Relaunch installed app**

Run:

```bash
pgrep -af '/Users/chunqiu/Applications/PaperCodex.app/Contents/MacOS/PaperCodexApp|PaperCodexApp' || true
pkill -f '/Users/chunqiu/Applications/PaperCodex.app/Contents/MacOS/PaperCodexApp|PaperCodexApp' || true
open /Users/chunqiu/Applications/PaperCodex.app
sleep 2
pgrep -af '/Users/chunqiu/Applications/PaperCodex.app/Contents/MacOS/PaperCodexApp|PaperCodexApp'
```

Expected: a new `/Users/chunqiu/Applications/PaperCodex.app/Contents/MacOS/PaperCodexApp` PID is reported.

- [ ] **Step 4: Completion audit**

Verify:

- `git status --short --branch` has no tracked changes.
- `.idea/` remains untracked and unstaged.
- Recent commits include the plan and implementation commits.
- Collections source contains `CollectionAIDock`, `CollectionSelectionPanel`, `CollectionFieldPanel`, `CollectionRunsPanel`, and optional selection prompt context.

If verification required fixes, commit them:

```bash
git add Sources/PaperCodexApp/CollectionView.swift Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "fix: polish collection AI workbench"
```
