import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftBaseURL = ""
    @State private var draftToken = ""

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 232, idealWidth: 260, maxWidth: 310)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    feedConnection
                    storageRules
                    cacheControls
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .frame(minWidth: 720)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            draftBaseURL = model.arxivFeedBaseURL
            draftToken = model.arxivFeedToken
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.system(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                navButton(title: "Library", systemImage: "books.vertical") {
                    model.goToLibrary()
                }
                navButton(title: "Discover", systemImage: "sparkle.magnifyingglass") {
                    model.showDiscover()
                }
                navButton(title: "Settings", systemImage: "gearshape", selected: true) {}
            }

            Spacer()
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 30, weight: .semibold))
            Text("Feed connection, disposable cache, and saved-paper organization.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var feedConnection: some View {
        settingsSection(title: "CodeArXiv Feed", systemImage: "server.rack") {
            TextField("Base URL", text: $draftBaseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("API token", text: $draftToken)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    model.setArxivFeedConnection(baseURL: draftBaseURL, token: draftToken)
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                } label: {
                    Label("Save & Connect", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                } label: {
                    Label("Refresh Feed", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var storageRules: some View {
        settingsSection(title: "Saved Paper Organization", systemImage: "folder.badge.gearshape") {
            Picker("Folder rule", selection: Binding(
                get: { model.arxivSaveOrganization },
                set: { model.setArxivSaveOrganization($0) }
            )) {
                ForEach(ArxivSaveOrganization.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.radioGroup)

            pathRow(label: "Library root", value: model.paperLibraryRootPath)
        }
    }

    private var cacheControls: some View {
        settingsSection(title: "Disposable Cache", systemImage: "internaldrive") {
            pathRow(label: "Cache root", value: model.arxivDisposableCachePath)
            HStack {
                Button(role: .destructive) {
                    model.clearArxivCaches()
                } label: {
                    Label("Clear arXiv Cache", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Text("Clears thumbnails, feed JSON, temporary PDFs, and unsaved opened papers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pathRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func navButton(title: String, systemImage: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
