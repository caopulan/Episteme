import PaperCodexCore
import SwiftUI

struct SaveToLibraryCategorySelection: Equatable {
    var categoryIDs: [String]
    var newCategoryNames: [String]

    static let empty = SaveToLibraryCategorySelection(categoryIDs: [], newCategoryNames: [])
}

struct SaveToLibrarySheet: View {
    var paperTitle: String
    var detail: String?
    var libraryCategories: [PaperCodexCore.Category]
    var initialCategoryIDs: [String]
    var onSave: (SaveToLibraryCategorySelection) -> Void
    var onCancel: () -> Void

    @State private var selectedCategoryIDs: Set<String>
    @State private var newCategoryName = ""

    init(
        paperTitle: String,
        detail: String? = nil,
        libraryCategories: [PaperCodexCore.Category],
        initialCategoryIDs: [String] = [],
        onSave: @escaping (SaveToLibraryCategorySelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.paperTitle = paperTitle
        self.detail = detail
        self.libraryCategories = libraryCategories
        self.initialCategoryIDs = initialCategoryIDs
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedCategoryIDs = State(initialValue: Set(initialCategoryIDs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            selectedCategories
            categoryPicker
            newCategoryRow
            Divider()
            actionRow
        }
        .padding(22)
        .frame(width: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.paperCodexSystem(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Save to Library")
                    .font(.title3.weight(.semibold))
                Text(paperTitle)
                    .font(.paperCodexSystem(size: 13, weight: .medium))
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedCategories: some View {
        let categories = selectedLibraryCategories
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Selected Categories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(categories) { category in
                        Button {
                            selectedCategoryIDs.remove(category.id)
                        } label: {
                            HStack(spacing: 5) {
                                Text(categoryDisplayName(category))
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.paperCodexSystem(size: 9, weight: .bold))
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var categoryPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if libraryCategories.isEmpty {
                    Text("No categories yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(libraryCategories) { category in
                        Button {
                            toggle(category.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedCategoryIDs.contains(category.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedCategoryIDs.contains(category.id) ? Color.accentColor : Color.secondary)
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(categoryDisplayName(category))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.paperCodexSystem(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedCategoryIDs.contains(category.id) ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 230)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var newCategoryRow: some View {
        HStack(spacing: 8) {
            TextField("New category", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "plus")
                .foregroundStyle(trimmedNewCategoryName.isEmpty ? Color.secondary : Color.accentColor)
                .frame(width: 18, height: 18)
                .help("Create category on save")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel", action: onCancel)
            Button {
                onSave(
                    SaveToLibraryCategorySelection(
                        categoryIDs: selectedCategoryIDsInOrder,
                        newCategoryNames: trimmedNewCategoryName.isEmpty ? [] : [trimmedNewCategoryName]
                    )
                )
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCategoryIDs.isEmpty && trimmedNewCategoryName.isEmpty)
        }
    }

    private var selectedLibraryCategories: [PaperCodexCore.Category] {
        libraryCategories.filter { selectedCategoryIDs.contains($0.id) }
    }

    private var selectedCategoryIDsInOrder: [String] {
        libraryCategories.map(\.id).filter { selectedCategoryIDs.contains($0) }
    }

    private var trimmedNewCategoryName: String {
        newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle(_ categoryID: String) {
        if selectedCategoryIDs.contains(categoryID) {
            selectedCategoryIDs.remove(categoryID)
        } else {
            selectedCategoryIDs.insert(categoryID)
        }
    }

    private func categoryDisplayName(_ category: PaperCodexCore.Category) -> String {
        var names = [category.name]
        var visited = Set([category.id])
        var parentID = category.parentID
        while let id = parentID,
              !visited.contains(id),
              let parent = libraryCategories.first(where: { $0.id == id }) {
            names.append(parent.name)
            visited.insert(parent.id)
            parentID = parent.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}
