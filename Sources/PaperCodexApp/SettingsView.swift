import AppKit
import PaperCodexCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftArxivCategories = ""
    @State private var draftWhitelistTags = ""
    @State private var draftBlacklistTags = ""
    @State private var draftSimilarityCategoryIDs: Set<String> = []
    @State private var draftAutoEnrichOnOpen = false
    @State private var draftAutoEnrichOnSave = false
    @State private var draftCodexSystemPrompt = PromptBuilder.defaultSystemPrompt
    @State private var draftDiscoverCodexModel = ""
    @State private var draftDiscoverCodexReasoningEffort: CodexReasoningEffort = .default
    @State private var draftDiscoverCodexConcurrency = 10
    @State private var draftChatMessageFontSize = ChatAppearanceDefaults.defaultMessageFontSize
    @State private var draftChatComposerFontSize = ChatAppearanceDefaults.defaultComposerFontSize
    @State private var draftChatFontFamily: ChatFontFamily = .system
    @State private var draftEmbeddingEnabled = false
    @State private var draftEmbeddingBaseURL = ""
    @State private var draftEmbeddingAPIKey = ""
    @State private var draftEmbeddingModel = ""
    @State private var newPromptTitle = ""
    @State private var newPromptContent = ""
    @State private var isEditingCodexSystemPrompt = false
    @State private var editingPrompt: QuickPrompt?
    @State private var editingPromptTitle = ""
    @State private var editingPromptContent = ""

    private var isArxivFeedDirty: Bool {
        splitDraftList(draftArxivCategories) != model.localDiscoverPreferences.normalized.categories
    }

    private var isRankingDirty: Bool {
        let preferences = model.localDiscoverPreferences.normalized
        return splitDraftList(draftWhitelistTags) != preferences.whitelistTags
            || splitDraftList(draftBlacklistTags) != preferences.blacklistTags
            || draftSimilarityCategoryIDs != Set(model.similarityCategoryIDsForSettings())
    }

    private var isEnrichmentDirty: Bool {
        let enrichment = model.localDiscoverPreferences.normalized.enrichment
        return draftAutoEnrichOnOpen != enrichment.autoEnrichOnOpen
            || draftAutoEnrichOnSave != enrichment.autoEnrichOnSave
    }

    private var isProcessingDirty: Bool {
        draftDiscoverCodexModel.trimmingCharacters(in: .whitespacesAndNewlines) != model.discoverCodexModelOverride
            || draftDiscoverCodexReasoningEffort != model.discoverCodexReasoningEffort
            || draftDiscoverCodexConcurrency != model.discoverCodexConcurrency
    }

    private var isChatAppearanceDirty: Bool {
        ChatAppearanceDefaults.clampedMessageFontSize(draftChatMessageFontSize) != model.chatMessageFontSize
            || ChatAppearanceDefaults.clampedComposerFontSize(draftChatComposerFontSize) != model.chatComposerFontSize
            || draftChatFontFamily != model.chatFontFamily
    }

    private var isEmbeddingDirty: Bool {
        let embedding = model.localDiscoverPreferences.normalized.embedding
        return draftEmbeddingEnabled != embedding.enabled
            || draftEmbeddingBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) != embedding.baseURL
            || draftEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines) != embedding.model
            || !draftEmbeddingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var codexDefaultModelLabel: String {
        let trimmed = model.codexDefaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Codex default" : "Codex default (\(trimmed))"
    }

    var body: some View {
        SidebarSplitLayout(minContentWidth: 760) {
            sidebar
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    globalLanguageSettings
                    chatAppearanceSettings
                    arxivFeedSettings
                    localRankingSettings
                    codexEnrichmentSettings
                    codexSystemPromptSettings
                    codexMCPSettings
                    agentRuntimeSettings
                    discoverCodexProcessingSettings
                    embeddingProviderSettings
                    quickPromptSettings
                    storageRules
                    cacheControls
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .frame(minWidth: 0)
        }
        .sheet(item: $editingPrompt) { prompt in
            quickPromptEditSheet(prompt)
        }
        .sheet(isPresented: $isEditingCodexSystemPrompt) {
            codexSystemPromptEditSheet
        }
        .onAppear {
            syncLocalDrafts()
            model.refreshCacheStorageSummary()
        }
        .onChange(of: model.localDiscoverPreferences) { _, _ in
            syncLocalDrafts()
        }
        .onChange(of: model.categories) { _, _ in
            syncLocalDrafts()
        }
        .onChange(of: model.codexSystemPrompt) { _, newValue in
            draftCodexSystemPrompt = newValue
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Episteme")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            PrimaryNavigationSection()

            Spacer()
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.paperCodexSystem(size: 30, weight: .semibold))
            Text("Local arXiv, storage, ranking, and Codex preferences.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var arxivFeedSettings: some View {
        settingsSection(title: "arXiv Feed", systemImage: "network") {
            SettingsTextField(
                title: "Categories, comma separated",
                text: $draftArxivCategories,
                placeholder: "Categories, comma separated"
            )
            HStack {
                SettingsActionButton(
                    title: isArxivFeedDirty ? "Save Categories" : "Saved",
                    systemImage: isArxivFeedDirty ? "checkmark" : "checkmark.circle",
                    kind: .primary,
                    disabled: !isArxivFeedDirty
                ) {
                    model.setLocalArxivCategories(splitDraftList(draftArxivCategories))
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                }

                SettingsActionButton(
                    title: model.isRefreshingArxivDates ? "Refreshing" : "Refresh arXiv",
                    systemImage: "arrow.clockwise",
                    disabled: model.isRefreshingArxivDates
                ) {
                    Task {
                        await model.refreshArxivDatesAndFeed()
                    }
                }

                Spacer()

                Text(model.selectedArxivDate ?? "No cached date")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var globalLanguageSettings: some View {
        settingsSection(title: "Language", systemImage: "globe") {
            SettingsLanguageSegmentedControl(
                selection: model.globalLanguageMode,
                appLanguage: model.globalLanguageMode
            ) { mode in
                model.setGlobalLanguageMode(mode)
            }

            Text("Controls the whole app interface, Explore language, and the default Codex prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chatAppearanceSettings: some View {
        settingsSection(title: "Reader Chat Appearance", systemImage: "text.bubble") {
            SettingsChatFontSegmentedControl(selection: draftChatFontFamily) { family in
                draftChatFontFamily = family
            }

            SettingsFontSizeStepper(
                title: "Message text",
                value: draftChatMessageFontSize,
                range: ChatAppearanceDefaults.messageFontSizeRange,
                step: 1
            ) { size in
                draftChatMessageFontSize = size
            }

            SettingsFontSizeStepper(
                title: "Composer text",
                value: draftChatComposerFontSize,
                range: ChatAppearanceDefaults.composerFontSizeRange,
                step: 1
            ) { size in
                draftChatComposerFontSize = size
            }

            ChatAppearancePreview(
                messageFontSize: draftChatMessageFontSize,
                composerFontSize: draftChatComposerFontSize,
                fontFamily: draftChatFontFamily
            )

            HStack {
                SettingsActionButton(
                    title: isChatAppearanceDirty ? "Save Chat Appearance" : "Saved",
                    systemImage: isChatAppearanceDirty ? "checkmark" : "checkmark.circle",
                    kind: .primary,
                    disabled: !isChatAppearanceDirty
                ) {
                    model.setChatAppearance(
                        messageFontSize: draftChatMessageFontSize,
                        composerFontSize: draftChatComposerFontSize,
                        fontFamily: draftChatFontFamily
                    )
                    syncLocalDrafts()
                }

                SettingsActionButton(title: "Default", systemImage: "arrow.counterclockwise") {
                    model.resetChatAppearance()
                    syncLocalDrafts()
                }

                Spacer()

                Text("\(model.chatFontFamily.title) · \(Int(model.chatMessageFontSize))/\(Int(model.chatComposerFontSize)) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isChatAppearanceDirty ? .orange : .secondary)
            }
        }
    }

    private var localRankingSettings: some View {
        settingsSection(title: "Local Ranking", systemImage: "slider.horizontal.3") {
            SettingsTextField(
                title: "Whitelist tags, comma separated",
                text: $draftWhitelistTags,
                placeholder: "Whitelist tags, comma separated"
            )
            SettingsTextField(
                title: "Blacklist tags, comma separated",
                text: $draftBlacklistTags,
                placeholder: "Blacklist tags, comma separated"
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("Similarity categories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.categories) { category in
                            similarityCategoryRow(category)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                SettingsActionButton(
                    title: isRankingDirty ? "Save Ranking" : "Saved",
                    systemImage: isRankingDirty ? "line.3.horizontal.decrease.circle" : "checkmark.circle",
                    kind: .primary,
                    disabled: !isRankingDirty
                ) {
                    model.setLocalTagFilters(
                        whitelist: splitDraftList(draftWhitelistTags),
                        blacklist: splitDraftList(draftBlacklistTags)
                    )
                    model.setLocalSimilarityCategoryIDs(selectedSimilarityCategoryIDsInOrder)
                }

                Spacer()

                Text("\(model.localDiscoverPreferences.whitelistTags.count) white · \(model.localDiscoverPreferences.blacklistTags.count) black · \(draftSimilarityCategoryIDs.count)/\(model.categories.count) cats")
                    .font(.caption)
                    .foregroundStyle(isRankingDirty ? .orange : .secondary)
            }
        }
    }

    private func similarityCategoryRow(_ category: PaperCodexCore.Category) -> some View {
        SettingsCategoryToggleRow(
            title: categoryDisplayName(category),
            selected: draftSimilarityCategoryIDs.contains(category.id)
        ) {
            if draftSimilarityCategoryIDs.contains(category.id) {
                draftSimilarityCategoryIDs.remove(category.id)
            } else {
                draftSimilarityCategoryIDs.insert(category.id)
            }
        }
    }

    private var codexEnrichmentSettings: some View {
        settingsSection(title: "Codex Enrichment", systemImage: "sparkles") {
            SettingsCheckboxToggle(
                title: "Auto-enrich when opening arXiv papers",
                isOn: draftAutoEnrichOnOpen
            ) { isOn in
                draftAutoEnrichOnOpen = isOn
            }
            SettingsCheckboxToggle(
                title: "Auto-enrich when saving to Library",
                isOn: draftAutoEnrichOnSave
            ) { isOn in
                draftAutoEnrichOnSave = isOn
            }
            SettingsActionButton(
                title: isEnrichmentDirty ? "Save Enrichment" : "Saved",
                systemImage: isEnrichmentDirty ? "checkmark" : "checkmark.circle",
                kind: .primary,
                disabled: !isEnrichmentDirty
            ) {
                model.setLocalEnrichmentPreferences(
                    autoOpen: draftAutoEnrichOnOpen,
                    autoSave: draftAutoEnrichOnSave
                )
            }
        }
    }

    private var discoverCodexProcessingSettings: some View {
        settingsSection(title: "Explore Processing", systemImage: "cpu") {
            HStack(spacing: 12) {
                SettingsModelPopup(
                    selectedModelID: draftDiscoverCodexModel,
                    defaultModelLabel: codexDefaultModelLabel,
                    availableModelIDs: model.availableCodexModelIDs
                ) { modelID in
                    draftDiscoverCodexModel = modelID
                }

                SettingsReasoningEffortPopup(selection: draftDiscoverCodexReasoningEffort) { effort in
                    draftDiscoverCodexReasoningEffort = effort
                }
            }

            SettingsTextField(
                title: "Custom model override",
                text: $draftDiscoverCodexModel,
                placeholder: "Custom model override"
            )

            SettingsIntegerStepper(
                title: "Concurrent Codex processes",
                value: draftDiscoverCodexConcurrency,
                range: 1...20,
                step: 1
            ) { value in
                draftDiscoverCodexConcurrency = value
            }

            HStack {
                SettingsActionButton(
                    title: isProcessingDirty ? "Save Processing" : "Saved",
                    systemImage: isProcessingDirty ? "checkmark" : "checkmark.circle",
                    kind: .primary,
                    disabled: !isProcessingDirty
                ) {
                    model.setDiscoverCodexSettings(
                        modelOverride: draftDiscoverCodexModel,
                        concurrency: draftDiscoverCodexConcurrency,
                        reasoningEffort: draftDiscoverCodexReasoningEffort
                    )
                }

                SettingsActionButton(
                    title: model.isRefreshingCodexModels ? "Refreshing" : "Refresh Models",
                    systemImage: "arrow.clockwise",
                    disabled: model.isRefreshingCodexModels
                ) {
                    Task {
                        await model.refreshAvailableCodexModels()
                    }
                }

                Spacer()

                Text("\(model.discoverCodexConcurrency) workers · Think \(model.discoverCodexReasoningEffort.displayName)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codexSystemPromptSettings: some View {
        settingsSection(title: "Codex System Prompt", systemImage: "text.quote") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Template")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Workspace placeholder: \(PromptBuilder.workspacePathPlaceholder)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text("\(model.codexSystemPrompt.count) characters")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    SettingsActionButton(title: "Edit Prompt", systemImage: "pencil", kind: .primary) {
                        draftCodexSystemPrompt = model.codexSystemPrompt
                        isEditingCodexSystemPrompt = true
                    }
                    .help("Edit System Prompt")

                    SettingsActionButton(title: "Default", systemImage: "arrow.counterclockwise") {
                        model.resetCodexSystemPrompt()
                        draftCodexSystemPrompt = model.codexSystemPrompt
                    }
                    .help("Restore Default System Prompt")

                    Spacer()

                    Text(PromptBuilder.isBuiltInSystemPrompt(model.codexSystemPrompt) ? "Default" : "Custom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var codexMCPSettings: some View {
        settingsSection(title: "Episteme MCP", systemImage: "point.3.connected.trianglepath.dotted") {
            SettingsCheckboxToggle(
                title: "Enable for in-app Codex",
                isOn: model.inAppCodexMCPEnabled
            ) { isOn in
                model.setInAppCodexMCPEnabled(isOn)
            }

            HStack {
                Text(model.inAppCodexMCPStatusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex Plugin")
                        .font(.paperCodexSystem(size: 13, weight: .semibold))
                    Text(model.codexPluginInstallationStatus?.detail ?? "Not checked")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle((model.codexPluginInstallationStatus?.current ?? false) ? .green : .secondary)
                }

                Spacer()

                SettingsActionButton(
                    title: model.isInstallingCodexPlugin ? "Installing" : "Install / Update",
                    systemImage: "puzzlepiece.extension",
                    disabled: model.isInstallingCodexPlugin || !model.paperCodexMCPServerReady
                ) {
                    Task {
                        await model.installOrUpdateCodexPlugin()
                    }
                }
                .help("Install or update the Episteme plugin in local Codex")
            }
        }
    }

    private var agentRuntimeSettings: some View {
        settingsSection(title: "Agent Runtimes", systemImage: "terminal") {
            HStack(spacing: 12) {
                SettingsRuntimePopup(
                    title: "Chat",
                    profiles: model.agentRuntimeProfiles,
                    selectedID: model.selectedChatRuntimeID
                ) { runtimeID in
                    model.setSelectedChatRuntimeID(runtimeID)
                }

                SettingsRuntimePopup(
                    title: "Explore",
                    profiles: model.agentRuntimeProfiles,
                    selectedID: model.selectedEnrichmentRuntimeID
                ) { runtimeID in
                    model.setSelectedEnrichmentRuntimeID(runtimeID)
                }

                Spacer()

                SettingsActionButton(
                    title: model.isRefreshingAgentRuntimeDiagnostics ? "Checking" : "Check Runtimes",
                    systemImage: "arrow.clockwise",
                    disabled: model.isRefreshingAgentRuntimeDiagnostics
                ) {
                    Task {
                        await model.refreshAgentRuntimeDiagnostics()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.agentRuntimeProfiles) { profile in
                    agentRuntimeRow(profile)
                    if profile.id != model.agentRuntimeProfiles.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func agentRuntimeRow(_ profile: AgentRuntimeProfile) -> some View {
        let diagnostic = model.agentRuntimeDiagnostic(for: profile.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SettingsCheckboxToggle(
                    title: profile.displayName,
                    isOn: model.isAgentRuntimeEnabled(profile.id),
                    fontWeight: .semibold
                ) { isOn in
                    model.setAgentRuntimeEnabled(profile.id, enabled: isOn)
                }
                .frame(width: 190, alignment: .leading)

                Text(diagnostic?.title ?? "Not checked")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(diagnostic?.state.settingsColor ?? .secondary)

                Spacer()

                Text(profile.executableName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let path = diagnostic?.executablePath {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(diagnostic?.detail ?? "Executable has not been checked yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(model.agentRuntimeAuthSummary(for: profile.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 10) {
                if profile.backend == .hermes || profile.backend == .pi {
                    SettingsTextField(
                        title: "Provider",
                        text: Binding(
                        get: { model.agentRuntimeProviderOverride(for: profile.id) },
                        set: { model.setAgentRuntimeProviderOverride($0, for: profile.id) }
                    ),
                        placeholder: "Provider"
                    )
                    .frame(maxWidth: 150)
                }

                SettingsTextField(
                    title: profile.defaultModelID ?? "Model override",
                    text: Binding(
                        get: { model.agentRuntimeModelOverride(for: profile.id) },
                        set: { model.setAgentRuntimeModelOverride($0, for: profile.id) }
                    ),
                    placeholder: profile.defaultModelID ?? "Model override"
                )
                .frame(maxWidth: 220)

                SettingsMCPModePopup(selection: model.agentRuntimeMCPMode(for: profile.id)) { mode in
                    model.setAgentRuntimeMCPMode(mode, for: profile.id)
                }

                Spacer()

                Text(profile.capabilitySummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var embeddingProviderSettings: some View {
        settingsSection(title: "Embedding Provider", systemImage: "point.3.connected.trianglepath.dotted") {
            SettingsCheckboxToggle(
                title: "Enable embedding similarity",
                isOn: draftEmbeddingEnabled
            ) { isOn in
                draftEmbeddingEnabled = isOn
            }
            SettingsTextField(
                title: "Base URL",
                text: $draftEmbeddingBaseURL,
                placeholder: "Base URL"
            )
            SettingsSecureField(
                title: "API key (leave blank to keep saved)",
                text: $draftEmbeddingAPIKey,
                placeholder: "API key (leave blank to keep saved)"
            )
            SettingsTextField(
                title: "Model",
                text: $draftEmbeddingModel,
                placeholder: "Model"
            )
            HStack {
                SettingsActionButton(
                    title: isEmbeddingDirty ? "Save Embedding" : "Saved",
                    systemImage: isEmbeddingDirty ? "key" : "checkmark.circle",
                    kind: .primary,
                    disabled: !isEmbeddingDirty
                ) {
                    model.setEmbeddingProviderSettings(
                        enabled: draftEmbeddingEnabled,
                        baseURL: draftEmbeddingBaseURL,
                        apiKey: draftEmbeddingAPIKey,
                        model: draftEmbeddingModel
                    )
                }

                SettingsActionButton(
                    title: model.isTestingEmbeddingProvider ? "Testing" : "Test",
                    systemImage: "bolt.horizontal.circle",
                    disabled: model.isTestingEmbeddingProvider
                ) {
                    Task {
                        await model.testEmbeddingProvider(
                            baseURL: draftEmbeddingBaseURL,
                            apiKey: draftEmbeddingAPIKey,
                            model: draftEmbeddingModel
                        )
                    }
                }

                Spacer()

                Text(model.embeddingProviderTestStatus ?? (model.localDiscoverPreferences.embedding.enabled ? "Enabled" : "Disabled"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickPromptSettings: some View {
        settingsSection(title: "Quick Prompts", systemImage: "text.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.quickPrompts) { prompt in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(prompt.title)
                                .font(.paperCodexSystem(size: 13, weight: .semibold))
                            Text(prompt.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        PaperCodexIconButton(title: "Move Up", systemImage: "chevron.up") {
                            model.moveQuickPrompt(prompt, direction: -1)
                        }
                        PaperCodexIconButton(title: "Move Down", systemImage: "chevron.down") {
                            model.moveQuickPrompt(prompt, direction: 1)
                        }
                        PaperCodexIconButton(title: "Edit Prompt", systemImage: "pencil") {
                            editingPromptTitle = prompt.title
                            editingPromptContent = prompt.content
                            editingPrompt = prompt
                        }
                        PaperCodexIconButton(title: "Delete Prompt", systemImage: "trash", tint: .red) {
                            model.deleteQuickPrompt(prompt)
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                SettingsTextField(
                    title: "Prompt title",
                    text: $newPromptTitle,
                    placeholder: "Prompt title"
                )
                SettingsMultilineTextView(
                    title: "New quick prompt editor",
                    text: $newPromptContent,
                    placeholder: "Prompt content",
                    minHeight: 78
                )
                SettingsActionButton(
                    title: "Add Prompt",
                    systemImage: "plus",
                    disabled: newPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newPromptContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    model.addQuickPrompt(title: newPromptTitle, content: newPromptContent)
                    if model.errorMessage == nil {
                        newPromptTitle = ""
                        newPromptContent = ""
                    }
                }
            }
        }
    }

    private var storageRules: some View {
        settingsSection(title: "Saved Paper Organization", systemImage: "folder.badge.gearshape") {
            SettingsSaveOrganizationRadioGroup(selection: model.arxivSaveOrganization) { organization in
                model.setArxivSaveOrganization(organization)
            }

            pathRow(label: "Library root", value: model.paperLibraryRootPath)
        }
    }

    private var cacheControls: some View {
        settingsSection(title: "Disposable Cache", systemImage: "internaldrive") {
            pathRow(label: "Cache root", value: model.arxivDisposableCachePath)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.cacheStorageSummary.detailText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("arXiv \(CacheStorageSummary.formatBytes(model.cacheStorageSummary.arxivCacheBytes)) · thumbnails \(CacheStorageSummary.formatBytes(model.cacheStorageSummary.thumbnailBytes))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            HStack {
                SettingsActionButton(title: "Clear arXiv Cache", systemImage: "trash", kind: .destructive, role: .destructive) {
                    confirmClearArxivCache()
                }

                SettingsActionButton(title: "Refresh Size", systemImage: "arrow.clockwise") {
                    model.refreshCacheStorageSummary()
                }

                Text("Clears feed JSON, temporary PDFs, and unsaved opened papers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func confirmClearArxivCache() {
        PaperCodexNativeConfirmation.present(
            title: "Clear arXiv cache?",
            message: "This removes cached feed JSON, temporary PDFs, and unsaved opened arXiv papers.",
            confirmTitle: "Clear",
            style: .critical
        ) {
            model.clearArxivCaches()
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
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

    private var codexSystemPromptEditSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Edit System Prompt", systemImage: "text.quote")
                .font(.title3.weight(.semibold))
            Text("Workspace placeholder: \(PromptBuilder.workspacePathPlaceholder)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            SettingsMultilineTextView(
                title: "System prompt template editor",
                text: $draftCodexSystemPrompt,
                placeholder: "System prompt template",
                fontStyle: .monospaced,
                minHeight: 320
            )
            HStack {
                Text("\(draftCodexSystemPrompt.count) characters")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsActionButton(title: "Cancel") {
                    draftCodexSystemPrompt = model.codexSystemPrompt
                    isEditingCodexSystemPrompt = false
                }
                SettingsActionButton(title: "Default", systemImage: "arrow.counterclockwise") {
                    model.resetCodexSystemPrompt()
                    draftCodexSystemPrompt = model.codexSystemPrompt
                    isEditingCodexSystemPrompt = false
                }
                SettingsActionButton(
                    title: "Save",
                    systemImage: "checkmark",
                    kind: .primary,
                    disabled: draftCodexSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    model.setCodexSystemPrompt(draftCodexSystemPrompt)
                    isEditingCodexSystemPrompt = false
                }
            }
        }
        .padding(22)
        .frame(width: 720, height: 520)
    }

    private func quickPromptEditSheet(_ prompt: QuickPrompt) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Edit Quick Prompt", systemImage: "pencil")
                .font(.title3.weight(.semibold))
            SettingsTextField(
                title: "Prompt title",
                text: $editingPromptTitle,
                placeholder: "Prompt title"
            )
            SettingsMultilineTextView(
                title: "Quick prompt editor",
                text: $editingPromptContent,
                placeholder: "Prompt content",
                minHeight: 120
            )
            HStack {
                Spacer()
                SettingsActionButton(title: "Cancel") {
                    editingPrompt = nil
                }
                SettingsActionButton(
                    title: "Save",
                    kind: .primary,
                    disabled: editingPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editingPromptContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    model.updateQuickPrompt(prompt, title: editingPromptTitle, content: editingPromptContent)
                    editingPrompt = nil
                }
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            editingPromptTitle = prompt.title
            editingPromptContent = prompt.content
        }
    }

    private func pathRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                Text(value)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                PaperCodexIconButton(title: "Reveal in Finder", systemImage: "folder") {
                    model.revealPath(value)
                }
            }
        }
    }

    private func syncLocalDrafts() {
        let preferences = model.localDiscoverPreferences.normalized
        draftArxivCategories = preferences.categories.joined(separator: ", ")
        draftWhitelistTags = preferences.whitelistTags.joined(separator: ", ")
        draftBlacklistTags = preferences.blacklistTags.joined(separator: ", ")
        draftSimilarityCategoryIDs = Set(model.similarityCategoryIDsForSettings())
        draftAutoEnrichOnOpen = preferences.enrichment.autoEnrichOnOpen
        draftAutoEnrichOnSave = preferences.enrichment.autoEnrichOnSave
        draftCodexSystemPrompt = model.codexSystemPrompt
        draftDiscoverCodexModel = model.discoverCodexModelOverride
        draftDiscoverCodexReasoningEffort = model.discoverCodexReasoningEffort
        draftDiscoverCodexConcurrency = model.discoverCodexConcurrency
        draftChatMessageFontSize = model.chatMessageFontSize
        draftChatComposerFontSize = model.chatComposerFontSize
        draftChatFontFamily = model.chatFontFamily
        draftEmbeddingEnabled = preferences.embedding.enabled
        draftEmbeddingBaseURL = preferences.embedding.baseURL
        draftEmbeddingModel = preferences.embedding.model
        draftEmbeddingAPIKey = ""
    }

    private func splitDraftList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var selectedSimilarityCategoryIDsInOrder: [String] {
        model.categories.map(\.id).filter { draftSimilarityCategoryIDs.contains($0) }
    }

    private func categoryDisplayName(_ category: PaperCodexCore.Category) -> String {
        var names = [category.name]
        var visited = Set([category.id])
        var parentID = category.parentID
        while let id = parentID,
              !visited.contains(id),
              let parent = model.categories.first(where: { $0.id == id }) {
            names.append(parent.name)
            visited.insert(parent.id)
            parentID = parent.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}

private enum SettingsActionButtonKind {
    case primary
    case secondary
    case destructive

    var tint: Color {
        switch self {
        case .primary:
            Color.accentColor
        case .secondary:
            Color.secondary
        case .destructive:
            Color.red
        }
    }

    var panelKind: PaperCodexPanelButtonKind {
        switch self {
        case .primary:
            .primary
        case .secondary:
            .secondary
        case .destructive:
            .destructive
        }
    }
}

private struct ChatAppearancePreview: View {
    var messageFontSize: Double
    var composerFontSize: Double
    var fontFamily: ChatFontFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.paperCodexSystem(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("Agent response preview")
                        .font(fontFamily.swiftUIFont(size: max(11, messageFontSize - 4), weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Formula messages, citations, lists, and code blocks follow this reading size.")
                        .font(fontFamily.swiftUIFont(size: messageFontSize))
                        .lineSpacing(2)
                        .foregroundStyle(.primary.opacity(0.90))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            )

            Text("Composer text preview")
                .font(fontFamily.swiftUIFont(size: composerFontSize))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct SettingsLanguageSegmentedControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var selection: PaperCodexLanguageMode
    var appLanguage: PaperCodexLanguageMode
    var onSelect: (PaperCodexLanguageMode) -> Void

    var body: some View {
        NativeSettingsSegmentedControl(
            accessibilityLabel: "App language",
            items: PaperCodexLanguageMode.allCases.map { mode in
                NativeSettingsSegmentItem(id: mode.rawValue, title: mode.title(appLanguage: appLanguage))
            },
            selectedID: selection.rawValue,
            reduceMotion: reduceMotion
        ) { id in
            if let mode = PaperCodexLanguageMode(rawValue: id) {
                onSelect(mode)
            }
        }
        .frame(maxWidth: 280, minHeight: 28, maxHeight: 28, alignment: .leading)
        .help("App language")
    }
}

private struct SettingsChatFontSegmentedControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var selection: ChatFontFamily
    var onSelect: (ChatFontFamily) -> Void

    var body: some View {
        NativeSettingsSegmentedControl(
            accessibilityLabel: "Chat font",
            items: ChatFontFamily.allCases.map { family in
                NativeSettingsSegmentItem(id: family.rawValue, title: family.title)
            },
            selectedID: selection.rawValue,
            reduceMotion: reduceMotion
        ) { id in
            if let family = ChatFontFamily(rawValue: id) {
                onSelect(family)
            }
        }
        .frame(maxWidth: 360, minHeight: 28, maxHeight: 28, alignment: .leading)
        .help("Chat font")
    }
}

private struct NativeSettingsSegmentItem: Equatable {
    var id: String
    var title: String
}

private struct NativeSettingsSegmentedControl: NSViewRepresentable {
    var accessibilityLabel: String
    var items: [NativeSettingsSegmentItem]
    var selectedID: String
    var reduceMotion: Bool
    var action: (String) -> Void

    func makeNSView(context: Context) -> NativeSettingsSegmentedControlView {
        let view = NativeSettingsSegmentedControlView()
        view.apply(
            accessibilityLabel: accessibilityLabel,
            items: items,
            selectedID: selectedID,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativeSettingsSegmentedControlView, context: Context) {
        view.apply(
            accessibilityLabel: accessibilityLabel,
            items: items,
            selectedID: selectedID,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private final class NativeSettingsSegmentedControlView: NSSegmentedControl {
    private var segmentItems: [NativeSettingsSegmentItem] = []
    private var selectedID = ""
    private var reduceMotion = false
    private var pressHandler: (String) -> Void = { _ in }
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func accessibilityValue() -> Any? {
        segmentItems.first { $0.id == selectedID }?.title ?? ""
    }

    func apply(
        accessibilityLabel: String,
        items: [NativeSettingsSegmentItem],
        selectedID: String,
        reduceMotion: Bool,
        action: @escaping (String) -> Void
    ) {
        segmentItems = items
        self.selectedID = selectedID
        self.reduceMotion = reduceMotion
        pressHandler = action
        setAccessibilityLabel(accessibilityLabel)
        toolTip = accessibilityLabel

        if segmentCount != items.count {
            setSegmentCount(items.count)
        }
        for (index, item) in items.enumerated() {
            setLabel(item.title, forSegment: index)
            setToolTip(item.title, forSegment: index)
            setEnabled(true, forSegment: index)
        }
        selectedSegment = items.firstIndex { $0.id == selectedID } ?? -1
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        segmentStyle = .rounded
        trackingMode = .selectOne
        controlSize = .regular
        font = .systemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(selectionChanged)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        wantsLayer = true
    }

    private func setSegmentCount(_ count: Int) {
        segmentCount = count
    }

    @objc private func selectionChanged() {
        guard selectedSegment >= 0, selectedSegment < segmentItems.count else {
            return
        }
        let id = segmentItems[selectedSegment].id
        selectedID = id
        pressHandler(id)
        updateAppearance()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let targetScale: CGFloat
        if reduceMotion {
            targetScale = 1
        } else {
            targetScale = isPressed ? 0.992 : 1
        }

        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}

private struct SettingsModelPopup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var selectedModelID: String
    var defaultModelLabel: String
    var availableModelIDs: [String]
    var onSelect: (String) -> Void

    var body: some View {
        NativeSettingsPopupButton(
            accessibilityLabel: "Model",
            items: modelItems,
            selectedID: selectedModelID,
            reduceMotion: reduceMotion,
            action: onSelect
        )
        .frame(width: 300, height: 28, alignment: .leading)
        .help("Model")
    }

    private var modelItems: [NativeSettingsPopupItem] {
        var items = [NativeSettingsPopupItem(id: "", title: defaultModelLabel)]
        items += availableModelIDs.map { NativeSettingsPopupItem(id: $0, title: $0) }
        if !selectedModelID.isEmpty,
           !availableModelIDs.contains(selectedModelID) {
            items.append(NativeSettingsPopupItem(id: selectedModelID, title: "\(selectedModelID) (custom)"))
        }
        return items
    }
}

private struct SettingsReasoningEffortPopup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var selection: CodexReasoningEffort
    var onSelect: (CodexReasoningEffort) -> Void

    var body: some View {
        NativeSettingsPopupButton(
            accessibilityLabel: "Thinking",
            items: CodexReasoningEffort.allCases.map { effort in
                NativeSettingsPopupItem(id: effort.rawValue, title: "Think \(effort.displayName)")
            },
            selectedID: selection.rawValue,
            reduceMotion: reduceMotion
        ) { id in
            if let effort = CodexReasoningEffort(rawValue: id) {
                onSelect(effort)
            }
        }
        .frame(width: 160, height: 28, alignment: .leading)
        .help("Thinking")
    }
}

private struct SettingsRuntimePopup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var profiles: [AgentRuntimeProfile]
    var selectedID: String
    var onSelect: (String) -> Void

    var body: some View {
        NativeSettingsPopupButton(
            accessibilityLabel: title,
            items: profiles.map { profile in
                NativeSettingsPopupItem(id: profile.id, title: profile.displayName)
            },
            selectedID: selectedID,
            reduceMotion: reduceMotion,
            action: onSelect
        )
        .frame(width: 150, height: 28, alignment: .leading)
        .help(title)
    }
}

private struct SettingsMCPModePopup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var selection: AgentRuntimeMCPMode
    var onSelect: (AgentRuntimeMCPMode) -> Void

    var body: some View {
        NativeSettingsPopupButton(
            accessibilityLabel: "MCP",
            items: AgentRuntimeMCPMode.allCases.map { mode in
                NativeSettingsPopupItem(id: mode.rawValue, title: mode.settingsTitle)
            },
            selectedID: selection.rawValue,
            reduceMotion: reduceMotion
        ) { id in
            if let mode = AgentRuntimeMCPMode(rawValue: id) {
                onSelect(mode)
            }
        }
        .frame(width: 150, height: 28, alignment: .leading)
        .help("MCP")
    }
}

private struct NativeSettingsPopupItem: Equatable {
    var id: String
    var title: String
}

private struct SettingsSaveOrganizationRadioGroup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var selection: ArxivSaveOrganization
    var onSelect: (ArxivSaveOrganization) -> Void

    var body: some View {
        NativeSettingsRadioGroup(
            accessibilityLabel: "Folder rule",
            items: ArxivSaveOrganization.allCases.map { option in
                NativeSettingsRadioItem(id: option.rawValue, title: NSLocalizedString(option.title, comment: ""))
            },
            selectedItemID: selection.rawValue,
            reduceMotion: reduceMotion
        ) { id in
            if let organization = ArxivSaveOrganization(rawValue: id) {
                onSelect(organization)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .help("Folder rule")
    }
}

private struct NativeSettingsRadioItem: Equatable {
    var id: String
    var title: String
}

private struct NativeSettingsRadioGroup: NSViewRepresentable {
    var accessibilityLabel: String
    var items: [NativeSettingsRadioItem]
    var selectedItemID: String
    var reduceMotion: Bool
    var action: (String) -> Void

    func makeNSView(context: Context) -> NativeSettingsRadioGroupView {
        let view = NativeSettingsRadioGroupView()
        view.apply(
            accessibilityLabel: accessibilityLabel,
            items: items,
            selectedItemID: selectedItemID,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativeSettingsRadioGroupView, context: Context) {
        view.apply(
            accessibilityLabel: accessibilityLabel,
            items: items,
            selectedItemID: selectedItemID,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private final class NativeSettingsRadioGroupView: NSView {
    private let stackView = NSStackView()
    private var radioButtons: [NativeSettingsRadioButton] = []
    private var radioItems: [NativeSettingsRadioItem] = []
    private var selectedItemID = ""
    private var reduceMotion = false
    private var selectionHandler: (String) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: CGFloat(max(radioItems.count, 1) * 26))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(
        accessibilityLabel: String,
        items: [NativeSettingsRadioItem],
        selectedItemID: String,
        reduceMotion: Bool,
        action: @escaping (String) -> Void
    ) {
        self.radioItems = items
        self.selectedItemID = selectedItemID
        self.reduceMotion = reduceMotion
        selectionHandler = action
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(items.first { $0.id == selectedItemID }?.title ?? "")
        rebuildButtonsIfNeeded(items: items)
        updateSelection()
        invalidateIntrinsicContentSize()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        wantsLayer = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func rebuildButtonsIfNeeded(items: [NativeSettingsRadioItem]) {
        guard items != radioButtons.map({ NativeSettingsRadioItem(id: $0.identifier?.rawValue ?? "", title: $0.title) }) else {
            return
        }
        for button in radioButtons {
            stackView.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        radioButtons = items.enumerated().map { index, item in
            let button = NativeSettingsRadioButton(title: item.title, target: self, action: #selector(radioChanged))
            button.identifier = NSUserInterfaceItemIdentifier(item.id)
            button.tag = index
            button.setButtonType(.radio)
            button.isBordered = false
            button.controlSize = .regular
            button.font = .systemFont(ofSize: 13, weight: .regular)
            button.setAccessibilityLabel(item.title)
            button.setAccessibilityRole(.radioButton)
            button.toolTip = item.title
            stackView.addArrangedSubview(button)
            return button
        }
    }

    private func updateSelection() {
        for button in radioButtons {
            let isSelected = button.identifier?.rawValue == selectedItemID
            button.state = isSelected ? .on : .off
            button.setAccessibilityValue(isSelected ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: ""))
        }
    }

    @objc private func radioChanged(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < radioItems.count else {
            return
        }
        let id = radioItems[sender.tag].id
        selectedItemID = id
        setAccessibilityValue(radioItems[sender.tag].title)
        updateSelection()
        selectionHandler(id)
        pulse()
    }

    private func pulse() {
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.06)
        layer?.transform = CATransform3DMakeScale(reduceMotion ? 1 : 0.992, reduceMotion ? 1 : 0.992, 1)
        CATransaction.commit()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(self.reduceMotion)
            CATransaction.setAnimationDuration(self.reduceMotion ? 0 : 0.10)
            self.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }
}

private final class NativeSettingsRadioButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private struct NativeSettingsPopupButton: NSViewRepresentable {
    var accessibilityLabel: String
    var items: [NativeSettingsPopupItem]
    var selectedID: String
    var reduceMotion: Bool
    var action: (String) -> Void

    func makeNSView(context: Context) -> NativeSettingsPopupButtonView {
        let view = NativeSettingsPopupButtonView(frame: .zero)
        view.apply(
            accessibilityLabel: accessibilityLabel,
            items: items,
            selectedID: selectedID,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativeSettingsPopupButtonView, context: Context) {
        view.apply(
            accessibilityLabel: accessibilityLabel,
            items: items,
            selectedID: selectedID,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private final class NativeSettingsPopupButtonView: NSPopUpButton {
    private var popupItems: [NativeSettingsPopupItem] = []
    private var selectedID = ""
    private var reduceMotion = false
    private var changeHandler: (String) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect, pullsDown: false)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func accessibilityValue() -> Any? {
        popupItems.first { $0.id == selectedID }?.title ?? selectedItem?.title ?? ""
    }

    func apply(
        accessibilityLabel: String,
        items: [NativeSettingsPopupItem],
        selectedID: String,
        reduceMotion: Bool,
        action: @escaping (String) -> Void
    ) {
        popupItems = items
        self.selectedID = selectedID
        self.reduceMotion = reduceMotion
        changeHandler = action
        removeAllItems()
        for item in items {
            addItem(withTitle: item.title)
            lastItem?.representedObject = item.id
        }
        selectItem(withRepresentedObject: selectedID)
        if selectedItem == nil, !items.isEmpty {
            selectItem(at: 0)
            self.selectedID = items[0].id
        }
        toolTip = selectedItem?.title ?? accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(accessibilityValue())
    }

    override func mouseDown(with event: NSEvent) {
        pulse(pressed: true)
        super.mouseDown(with: event)
        pulse(pressed: false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        controlSize = .regular
        font = .systemFont(ofSize: 13, weight: .regular)
        target = self
        action = #selector(selectionChanged)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        wantsLayer = true
    }

    @objc private func selectionChanged() {
        guard let id = selectedItem?.representedObject as? String else {
            return
        }
        selectedID = id
        toolTip = selectedItem?.title
        setAccessibilityValue(accessibilityValue())
        changeHandler(id)
        pulse(pressed: false)
    }

    private func pulse(pressed: Bool) {
        let scale: CGFloat = reduceMotion || !pressed ? 1 : 0.992
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (pressed ? 0.05 : 0.10))
        layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }
}

private extension NSPopUpButton {
    func selectItem(withRepresentedObject representedObject: String) {
        guard let item = itemArray.first(where: { ($0.representedObject as? String) == representedObject }) else {
            return
        }
        select(item)
    }
}

    private struct SettingsTextField: View {
        var title: String
        @Binding var text: String
        var placeholder: String
        var onCommit: () -> Void = {}

        var body: some View {
            NativeSettingsTextField(
                title: title,
                text: $text,
                placeholder: placeholder,
                onCommit: onCommit
            )
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
            .help(title)
        }
    }

    private struct SettingsSecureField: View {
        var title: String
        @Binding var text: String
        var placeholder: String
        var onCommit: () -> Void = {}

        var body: some View {
            NativeSettingsSecureField(
                title: title,
                text: $text,
                placeholder: placeholder,
                onCommit: onCommit
            )
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
            .help(title)
        }
    }

    private enum SettingsMultilineTextFontStyle {
        case regular
        case monospaced

        var nsFont: NSFont {
            switch self {
            case .regular:
                .systemFont(ofSize: 13)
            case .monospaced:
                .monospacedSystemFont(ofSize: 13, weight: .regular)
            }
        }
    }

    private struct SettingsMultilineTextView: View {
        var title: String
        @Binding var text: String
        var placeholder: String
        var fontStyle: SettingsMultilineTextFontStyle = .regular
        var minHeight: CGFloat

        var body: some View {
            NativeSettingsMultilineTextView(
                title: title,
                text: $text,
                placeholder: placeholder,
                font: fontStyle.nsFont
            )
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .help(title)
        }
    }

    private struct NativeSettingsTextField: NSViewRepresentable {
        var title: String
        @Binding var text: String
        var placeholder: String
        var onCommit: () -> Void = {}

        func makeNSView(context: Context) -> NativeSettingsTextFieldView {
            let view = NativeSettingsTextFieldView()
            context.coordinator.update(text: $text, onCommit: onCommit)
            view.delegate = context.coordinator
            view.apply(
                title: title,
                text: text,
                placeholder: placeholder
            )
            return view
        }

        func updateNSView(_ view: NativeSettingsTextFieldView, context: Context) {
            context.coordinator.update(text: $text, onCommit: onCommit)
            view.delegate = context.coordinator
            view.apply(
                title: title,
                text: text,
                placeholder: placeholder
            )
        }

        func makeCoordinator() -> SettingsTextFieldCoordinator {
            SettingsTextFieldCoordinator(text: $text, onCommit: onCommit)
        }
    }

    private struct NativeSettingsSecureField: NSViewRepresentable {
        var title: String
        @Binding var text: String
        var placeholder: String
        var onCommit: () -> Void = {}

        func makeNSView(context: Context) -> NativeSettingsSecureFieldView {
            let view = NativeSettingsSecureFieldView()
            context.coordinator.update(text: $text, onCommit: onCommit)
            view.delegate = context.coordinator
            view.apply(
                title: title,
                text: text,
                placeholder: placeholder
            )
            return view
        }

        func updateNSView(_ view: NativeSettingsSecureFieldView, context: Context) {
            context.coordinator.update(text: $text, onCommit: onCommit)
            view.delegate = context.coordinator
            view.apply(
                title: title,
                text: text,
                placeholder: placeholder
            )
        }

        func makeCoordinator() -> SettingsTextFieldCoordinator {
            SettingsTextFieldCoordinator(text: $text, onCommit: onCommit)
        }
    }

    private struct NativeSettingsMultilineTextView: NSViewRepresentable {
        var title: String
        @Binding var text: String
        var placeholder: String
        var font: NSFont

        func makeNSView(context: Context) -> NativeSettingsMultilineTextViewContainer {
            let view = NativeSettingsMultilineTextViewContainer()
            context.coordinator.update(text: $text)
            view.apply(
                title: title,
                text: text,
                placeholder: placeholder,
                font: font,
                delegate: context.coordinator
            )
            return view
        }

        func updateNSView(_ view: NativeSettingsMultilineTextViewContainer, context: Context) {
            context.coordinator.update(text: $text)
            view.apply(
                title: title,
                text: text,
                placeholder: placeholder,
                font: font,
                delegate: context.coordinator
            )
        }

        func makeCoordinator() -> SettingsTextViewCoordinator {
            SettingsTextViewCoordinator(text: $text)
        }
    }

    private final class SettingsTextFieldCoordinator: NSObject, NSTextFieldDelegate {
        private var text: Binding<String>
        private var onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
            super.init()
        }

        func update(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else {
                return
            }
            text.wrappedValue = textField.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            onCommit()
        }
    }

    private final class SettingsTextViewCoordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
            super.init()
        }

        func update(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
        }
    }

    private final class NativeSettingsMultilineTextViewContainer: NSView {
        private let scrollView = NSScrollView()
        private let textView = NativeSettingsPromptTextView()
        private let placeholderLabel = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var isFlipped: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        func apply(
            title: String,
            text: String,
            placeholder: String,
            font: NSFont,
            delegate: NSTextViewDelegate
        ) {
            textView.delegate = delegate
            textView.font = font
            if textView.string != text && !textView.hasMarkedText() {
                textView.string = text
            }
            placeholderLabel.stringValue = placeholder
            placeholderLabel.font = font
            placeholderLabel.isHidden = !textView.string.isEmpty
            textView.setAccessibilityLabel(title)
            setAccessibilityLabel(title)
        }

        private func setup() {
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            setAccessibilityElement(false)

            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.borderType = .bezelBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = true
            scrollView.backgroundColor = .controlBackgroundColor

            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainerInset = NSSize(width: 8, height: 7)
            textView.drawsBackground = true
            textView.backgroundColor = .controlBackgroundColor
            textView.allowsUndo = true
            textView.isRichText = false
            textView.importsGraphics = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isContinuousSpellCheckingEnabled = false

            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            placeholderLabel.textColor = .placeholderTextColor
            placeholderLabel.backgroundColor = .clear
            placeholderLabel.isBezeled = false
            placeholderLabel.isEditable = false
            placeholderLabel.isSelectable = false

            scrollView.documentView = textView
            addSubview(scrollView)
            addSubview(placeholderLabel)

            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
                placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
                placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
            ])
        }
    }

    private final class NativeSettingsPromptTextView: NSTextView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }
    }

    private final class NativeSettingsTextFieldView: NSTextField {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 28)
        }

        override var isFlipped: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        func apply(title: String, text: String, placeholder: String) {
            setAccessibilityLabel(title)
            setAccessibilityValue(text)
            font = .systemFont(ofSize: 13)
            let fieldEditorHasMarkedText = (currentEditor() as? NSTextView)?.hasMarkedText() == true
            if stringValue != text && !fieldEditorHasMarkedText {
                stringValue = text
            }
            placeholderString = placeholder
            toolTip = title
        }

        private func setup() {
            translatesAutoresizingMaskIntoConstraints = false
            isBordered = true
            bezelStyle = .roundedBezel
            isBezeled = true
            usesSingleLineMode = true
            lineBreakMode = .byTruncatingTail
            focusRingType = .default
            font = .systemFont(ofSize: 13)
            setAccessibilityRole(.textField)
        }
    }

    private final class NativeSettingsSecureFieldView: NSSecureTextField {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 28)
        }

        override var isFlipped: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        func apply(title: String, text: String, placeholder: String) {
            setAccessibilityLabel(title)
            setAccessibilityValue(text.isEmpty ? "" : "\(text.count) characters")
            font = .systemFont(ofSize: 13)
            let fieldEditorHasMarkedText = (currentEditor() as? NSTextView)?.hasMarkedText() == true
            if stringValue != text && !fieldEditorHasMarkedText {
                stringValue = text
            }
            placeholderString = placeholder
            toolTip = title
        }

        private func setup() {
            translatesAutoresizingMaskIntoConstraints = false
            isBordered = true
            usesSingleLineMode = true
            lineBreakMode = .byTruncatingTail
            focusRingType = .default
            font = .systemFont(ofSize: 13)
            setAccessibilityRole(.textField)
        }
    }

    private struct SettingsIntegerStepper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var onChange: (Int) -> Void

    var body: some View {
        NativeSettingsIntegerStepper(
            title: title,
            value: value,
            range: range,
            step: step,
            reduceMotion: reduceMotion,
            onChange: onChange
        )
        .frame(width: 260, height: 28, alignment: .leading)
        .help(title)
    }
}

private struct NativeSettingsIntegerStepper: NSViewRepresentable {
    var title: String
    var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var reduceMotion: Bool
    var onChange: (Int) -> Void

    func makeNSView(context: Context) -> NativeSettingsIntegerStepperView {
        let view = NativeSettingsIntegerStepperView()
        view.apply(
            title: title,
            value: value,
            range: range,
            step: step,
            reduceMotion: reduceMotion,
            onChange: onChange
        )
        return view
    }

    func updateNSView(_ view: NativeSettingsIntegerStepperView, context: Context) {
        view.apply(
            title: title,
            value: value,
            range: range,
            step: step,
            reduceMotion: reduceMotion,
            onChange: onChange
        )
    }
}

private final class NativeSettingsIntegerStepperView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let stepper = NSStepper()
    private var range: ClosedRange<Int> = 0...1
    private var reduceMotion = false
    private var changeHandler: (Int) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        step: Int,
        reduceMotion: Bool,
        onChange: @escaping (Int) -> Void
    ) {
        self.range = range
        self.reduceMotion = reduceMotion
        changeHandler = onChange

        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        labelField.stringValue = "\(title): \(clampedValue)"
        labelField.toolTip = labelField.stringValue
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = Double(step)
        stepper.doubleValue = Double(clampedValue)
        stepper.setAccessibilityLabel(title)
        stepper.setAccessibilityValue("\(clampedValue)")
        stepper.toolTip = title
        setAccessibilityLabel(title)
        setAccessibilityValue("\(clampedValue)")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        wantsLayer = true

        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.font = .systemFont(ofSize: 13, weight: .regular)
        labelField.textColor = .labelColor
        labelField.lineBreakMode = .byTruncatingTail
        labelField.maximumNumberOfLines = 1

        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.controlSize = .small
        stepper.target = self
        stepper.action = #selector(stepperChanged)
        stepper.setContentHuggingPriority(.required, for: .horizontal)

        [labelField, stepper].forEach(addSubview(_:))

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: stepper.leadingAnchor, constant: -8),
            stepper.trailingAnchor.constraint(equalTo: trailingAnchor),
            stepper.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func stepperChanged() {
        let rawValue = Int(stepper.doubleValue.rounded())
        let clampedValue = min(max(rawValue, range.lowerBound), range.upperBound)
        stepper.doubleValue = Double(clampedValue)
        changeHandler(clampedValue)
        pulse()
    }

    private func pulse() {
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.06)
        layer?.transform = CATransform3DMakeScale(reduceMotion ? 1 : 0.992, reduceMotion ? 1 : 0.992, 1)
        CATransaction.commit()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(self.reduceMotion)
            CATransaction.setAnimationDuration(self.reduceMotion ? 0 : 0.10)
            self.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }
}

private struct SettingsFontSizeStepper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var onChange: (Double) -> Void

    var body: some View {
        NativeSettingsFontSizeStepper(
            title: title,
            value: value,
            range: range,
            step: step,
            reduceMotion: reduceMotion,
            onChange: onChange
        )
        .frame(width: 190, height: 28, alignment: .leading)
        .help(title)
    }
}

private struct NativeSettingsFontSizeStepper: NSViewRepresentable {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var reduceMotion: Bool
    var onChange: (Double) -> Void

    func makeNSView(context: Context) -> NativeSettingsFontSizeStepperView {
        let view = NativeSettingsFontSizeStepperView()
        view.apply(
            title: title,
            value: value,
            range: range,
            step: step,
            reduceMotion: reduceMotion,
            onChange: onChange
        )
        return view
    }

    func updateNSView(_ view: NativeSettingsFontSizeStepperView, context: Context) {
        view.apply(
            title: title,
            value: value,
            range: range,
            step: step,
            reduceMotion: reduceMotion,
            onChange: onChange
        )
    }
}

private final class NativeSettingsFontSizeStepperView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let stepper = NSStepper()
    private var range: ClosedRange<Double> = 0...1
    private var step: Double = 1
    private var reduceMotion = false
    private var changeHandler: (Double) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 190, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        reduceMotion: Bool,
        onChange: @escaping (Double) -> Void
    ) {
        self.range = range
        self.step = step
        self.reduceMotion = reduceMotion
        changeHandler = onChange

        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        labelField.stringValue = "\(title): \(Int(clampedValue)) pt"
        labelField.toolTip = labelField.stringValue
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = step
        stepper.doubleValue = clampedValue
        stepper.setAccessibilityLabel(title)
        stepper.setAccessibilityValue("\(Int(clampedValue)) pt")
        stepper.toolTip = title
        setAccessibilityLabel(title)
        setAccessibilityValue("\(Int(clampedValue)) pt")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        wantsLayer = true

        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.font = .systemFont(ofSize: 13, weight: .regular)
        labelField.textColor = .labelColor
        labelField.lineBreakMode = .byTruncatingTail
        labelField.maximumNumberOfLines = 1

        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.controlSize = .small
        stepper.target = self
        stepper.action = #selector(stepperChanged)
        stepper.setContentHuggingPriority(.required, for: .horizontal)

        [labelField, stepper].forEach(addSubview(_:))

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: stepper.leadingAnchor, constant: -8),
            stepper.trailingAnchor.constraint(equalTo: trailingAnchor),
            stepper.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func stepperChanged() {
        let clampedValue = min(max(stepper.doubleValue, range.lowerBound), range.upperBound)
        stepper.doubleValue = clampedValue
        changeHandler(clampedValue)
        pulse()
    }

    private func pulse() {
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.06)
        layer?.transform = CATransform3DMakeScale(reduceMotion ? 1 : 0.992, reduceMotion ? 1 : 0.992, 1)
        CATransaction.commit()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(self.reduceMotion)
            CATransaction.setAnimationDuration(self.reduceMotion ? 0 : 0.10)
            self.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }
}

private struct SettingsCheckboxToggle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var isOn: Bool
    var fontWeight: NSFont.Weight = .regular
    var action: (Bool) -> Void

    var body: some View {
        NativeSettingsCheckboxToggle(
            title: title,
            isOn: isOn,
            fontWeight: fontWeight,
            reduceMotion: reduceMotion,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .leading)
        .help(title)
    }
}

private struct NativeSettingsCheckboxToggle: NSViewRepresentable {
    var title: String
    var isOn: Bool
    var fontWeight: NSFont.Weight
    var reduceMotion: Bool
    var action: (Bool) -> Void

    func makeNSView(context: Context) -> NativeSettingsCheckboxToggleButtonView {
        let view = NativeSettingsCheckboxToggleButtonView()
        view.apply(title: title, isOn: isOn, fontWeight: fontWeight, reduceMotion: reduceMotion, action: action)
        return view
    }

    func updateNSView(_ view: NativeSettingsCheckboxToggleButtonView, context: Context) {
        view.apply(title: title, isOn: isOn, fontWeight: fontWeight, reduceMotion: reduceMotion, action: action)
    }
}

private final class NativeSettingsCheckboxToggleButtonView: NSButton {
    private var isChecked = false
    private var reduceMotion = false
    private var pressHandler: (Bool) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 26)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func accessibilityValue() -> Any? {
        isChecked ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: "")
    }

    override func accessibilityPerformPress() -> Bool {
        performToggle()
        return true
    }

    func apply(title: String, isOn: Bool, fontWeight: NSFont.Weight, reduceMotion: Bool, action: @escaping (Bool) -> Void) {
        self.title = title
        self.isChecked = isOn
        self.reduceMotion = reduceMotion
        pressHandler = action
        font = .systemFont(ofSize: 13, weight: fontWeight)
        state = isOn ? .on : .off
        toolTip = title
        setAccessibilityLabel(title)
        setAccessibilityValue(isOn ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: ""))
    }

    override func mouseDown(with event: NSEvent) {
        pulse(pressed: true)
        performToggle()
        DispatchQueue.main.async { [weak self] in
            self?.pulse(pressed: false)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            pulse(pressed: true)
            performToggle()
            DispatchQueue.main.async { [weak self] in
                self?.pulse(pressed: false)
            }
            return
        }
        super.keyDown(with: event)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setButtonType(.switch)
        isBordered = false
        controlSize = .regular
        font = .systemFont(ofSize: 13, weight: .regular)
        imagePosition = .imageLeading
        alignment = .left
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        wantsLayer = true
    }

    private func performToggle() {
        let nextValue = !isChecked
        isChecked = nextValue
        state = nextValue ? .on : .off
        pressHandler(nextValue)
    }

    private func pulse(pressed: Bool) {
        let scale: CGFloat = reduceMotion || !pressed ? 1 : 0.992
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (pressed ? 0.05 : 0.10))
        layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }
}

private struct SettingsCategoryToggleRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        NativeSettingsCategoryToggleButton(
            title: title,
            selected: selected,
            reduceMotion: reduceMotion,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .help(title)
    }
}

private struct NativeSettingsCategoryToggleButton: NSViewRepresentable {
    var title: String
    var selected: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativeSettingsCategoryToggleButtonView {
        let view = NativeSettingsCategoryToggleButtonView()
        view.apply(title: title, selected: selected, reduceMotion: reduceMotion, action: action)
        return view
    }

    func updateNSView(_ view: NativeSettingsCategoryToggleButtonView, context: Context) {
        view.apply(title: title, selected: selected, reduceMotion: reduceMotion, action: action)
    }
}

private final class NativeSettingsCategoryToggleButtonView: NSButton {
    private enum Metrics {
        static let rowHeight: CGFloat = 30
        static let horizontalPadding: CGFloat = 8
        static let iconSize: CGFloat = 15
        static let folderSize: CGFloat = 14
        static let checkFolderSpacing: CGFloat = 7
        static let folderTitleSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 6
    }

    private let checkImageView = NSImageView()
    private let folderImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var isHovering = false
    private var isPressed = false
    private var isSelectedRow = false
    private var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Metrics.rowHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func accessibilityValue() -> Any? {
        isSelectedRow ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: "")
    }

    override func accessibilityPerformPress() -> Bool {
        pressHandler()
        return true
    }

    func apply(title: String, selected: Bool, reduceMotion: Bool, action: @escaping () -> Void) {
        pressHandler = action
        isSelectedRow = selected
        self.reduceMotion = reduceMotion
        self.title = ""
        state = selected ? .on : .off
        toolTip = title
        titleLabel.stringValue = title
        checkImageView.image = NSImage(
            systemSymbolName: selected ? "checkmark.square.fill" : "square",
            accessibilityDescription: selected ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: "")
        )
        folderImageView.image = NSImage(systemSymbolName: "folder", accessibilityDescription: title)
        setAccessibilityLabel(title)
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        pressHandler()
        DispatchQueue.main.async { [weak self] in
            self?.setPressed(false)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            setPressed(true)
            pressHandler()
            DispatchQueue.main.async { [weak self] in
                self?.setPressed(false)
            }
            return
        }
        super.keyDown(with: event)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.switch)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.masksToBounds = false

        checkImageView.translatesAutoresizingMaskIntoConstraints = false
        checkImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        checkImageView.imageScaling = .scaleProportionallyDown

        folderImageView.translatesAutoresizingMaskIntoConstraints = false
        folderImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        folderImageView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        [checkImageView, folderImageView, titleLabel].forEach(addSubview(_:))

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.rowHeight),
            checkImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            checkImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkImageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            checkImageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
            folderImageView.leadingAnchor.constraint(equalTo: checkImageView.trailingAnchor, constant: Metrics.checkFolderSpacing),
            folderImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            folderImageView.widthAnchor.constraint(equalToConstant: Metrics.folderSize),
            folderImageView.heightAnchor.constraint(equalToConstant: Metrics.folderSize),
            titleLabel.leadingAnchor.constraint(equalTo: folderImageView.trailingAnchor, constant: Metrics.folderTitleSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Metrics.horizontalPadding)
        ])
        updateAppearance()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        checkImageView.contentTintColor = isSelectedRow ? accent : NSColor.secondaryLabelColor
        folderImageView.contentTintColor = isSelectedRow ? accent.withAlphaComponent(0.86) : NSColor.secondaryLabelColor
        titleLabel.textColor = (isSelectedRow || isPressed || isHovering)
            ? NSColor.labelColor.withAlphaComponent(0.92)
            : NSColor.labelColor.withAlphaComponent(0.82)

        let background: NSColor
        let border: NSColor
        if isPressed {
            background = accent.withAlphaComponent(0.16)
            border = accent.withAlphaComponent(0.44)
        } else if isSelectedRow {
            background = accent.withAlphaComponent(0.10)
            border = accent.withAlphaComponent(0.26)
        } else if isHovering {
            background = accent.withAlphaComponent(0.07)
            border = accent.withAlphaComponent(0.22)
        } else {
            background = .controlBackgroundColor
            border = .clear
        }

        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor

        let targetScale: CGFloat
        if reduceMotion {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.985
        } else {
            targetScale = isHovering ? 1.01 : 1
        }

        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}

private struct SettingsActionButton: View {
    var title: String
    var systemImage: String?
    var kind: SettingsActionButtonKind = .secondary
    var disabled = false
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        PaperCodexPanelButton(
            title: title,
            systemImage: systemImage,
            kind: kind.panelKind,
            disabled: disabled,
            role: role,
            action: action
        )
    }
}

private extension AgentRuntimeMCPMode {
    var settingsTitle: String {
        switch self {
        case .codexConfigOverrides:
            "Codex config"
        case .mcpConfigFile:
            "MCP file"
        case .configuredExternally:
            "External"
        case .workspaceOnly:
            "Workspace"
        }
    }
}

private extension AgentRuntimeDiagnosticState {
    var settingsColor: Color {
        switch self {
        case .checking:
            .secondary
        case .ready:
            .green
        case .warning:
            .orange
        case .blocked:
            .red
        }
    }
}

private extension AgentRuntimeProfile {
    var capabilitySummary: String {
        var parts: [String] = []
        if supportsNonInteractiveRuns {
            parts.append("chat")
        }
        if supportsPTY {
            parts.append("tui")
        }
        if supportsStructuredOutput {
            parts.append("json")
        }
        if supportsMCPConfig {
            parts.append("mcp")
        }
        return parts.joined(separator: " · ")
    }
}
