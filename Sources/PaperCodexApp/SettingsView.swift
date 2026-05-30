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
    @State private var isConfirmingClearCache = false
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
        .alert("Clear arXiv cache?", isPresented: $isConfirmingClearCache) {
            Button("Clear", role: .destructive) {
                model.clearArxivCaches()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes cached feed JSON, temporary PDFs, and unsaved opened arXiv papers.")
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
            TextField("Categories, comma separated", text: $draftArxivCategories)
                .textFieldStyle(.roundedBorder)
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
            Picker("App language", selection: Binding(
                get: { model.globalLanguageMode },
                set: { model.setGlobalLanguageMode($0) }
            )) {
                ForEach(PaperCodexLanguageMode.allCases) { mode in
                    Text(mode.title(appLanguage: model.globalLanguageMode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Controls the whole app interface, Explore language, and the default Codex prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chatAppearanceSettings: some View {
        settingsSection(title: "Reader Chat Appearance", systemImage: "text.bubble") {
            Picker("Chat font", selection: $draftChatFontFamily) {
                ForEach(ChatFontFamily.allCases) { family in
                    Text(family.title).tag(family)
                }
            }
            .pickerStyle(.segmented)

            Stepper(
                "Message text: \(Int(ChatAppearanceDefaults.clampedMessageFontSize(draftChatMessageFontSize))) pt",
                value: $draftChatMessageFontSize,
                in: ChatAppearanceDefaults.messageFontSizeRange,
                step: 1
            )

            Stepper(
                "Composer text: \(Int(ChatAppearanceDefaults.clampedComposerFontSize(draftChatComposerFontSize))) pt",
                value: $draftChatComposerFontSize,
                in: ChatAppearanceDefaults.composerFontSizeRange,
                step: 1
            )

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
            TextField("Whitelist tags, comma separated", text: $draftWhitelistTags)
                .textFieldStyle(.roundedBorder)
            TextField("Blacklist tags, comma separated", text: $draftBlacklistTags)
                .textFieldStyle(.roundedBorder)
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
            Toggle("Auto-enrich when opening arXiv papers", isOn: $draftAutoEnrichOnOpen)
                .toggleStyle(.checkbox)
            Toggle("Auto-enrich when saving to Library", isOn: $draftAutoEnrichOnSave)
                .toggleStyle(.checkbox)
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
            Picker("Model", selection: $draftDiscoverCodexModel) {
                Text(codexDefaultModelLabel).tag("")
                ForEach(model.availableCodexModelIDs, id: \.self) { modelID in
                    Text(modelID).tag(modelID)
                }
                if !draftDiscoverCodexModel.isEmpty,
                   !model.availableCodexModelIDs.contains(draftDiscoverCodexModel) {
                    Text("\(draftDiscoverCodexModel) (custom)").tag(draftDiscoverCodexModel)
                }
            }
            .pickerStyle(.menu)

            TextField("Custom model override", text: $draftDiscoverCodexModel)
                .textFieldStyle(.roundedBorder)

            Picker("Thinking", selection: $draftDiscoverCodexReasoningEffort) {
                ForEach(CodexReasoningEffort.allCases, id: \.self) { effort in
                    Text(effort.displayName).tag(effort)
                }
            }
            .pickerStyle(.menu)

            Stepper(
                "Concurrent Codex processes: \(draftDiscoverCodexConcurrency)",
                value: $draftDiscoverCodexConcurrency,
                in: 1...20
            )

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
            Toggle(
                "Enable for in-app Codex",
                isOn: Binding(
                    get: { model.inAppCodexMCPEnabled },
                    set: { model.setInAppCodexMCPEnabled($0) }
                )
            )
            .toggleStyle(.checkbox)

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
                Picker("Chat", selection: Binding(
                    get: { model.selectedChatRuntimeID },
                    set: { model.setSelectedChatRuntimeID($0) }
                )) {
                    ForEach(model.agentRuntimeProfiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Explore", selection: Binding(
                    get: { model.selectedEnrichmentRuntimeID },
                    set: { model.setSelectedEnrichmentRuntimeID($0) }
                )) {
                    ForEach(model.agentRuntimeProfiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

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
                Toggle(
                    profile.displayName,
                    isOn: Binding(
                        get: { model.isAgentRuntimeEnabled(profile.id) },
                        set: { model.setAgentRuntimeEnabled(profile.id, enabled: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.paperCodexSystem(size: 13, weight: .semibold))

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
                    TextField("Provider", text: Binding(
                        get: { model.agentRuntimeProviderOverride(for: profile.id) },
                        set: { model.setAgentRuntimeProviderOverride($0, for: profile.id) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150)
                }

                TextField(profile.defaultModelID ?? "Model override", text: Binding(
                    get: { model.agentRuntimeModelOverride(for: profile.id) },
                    set: { model.setAgentRuntimeModelOverride($0, for: profile.id) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

                Picker("MCP", selection: Binding(
                    get: { model.agentRuntimeMCPMode(for: profile.id) },
                    set: { model.setAgentRuntimeMCPMode($0, for: profile.id) }
                )) {
                    ForEach(AgentRuntimeMCPMode.allCases, id: \.self) { mode in
                        Text(mode.settingsTitle).tag(mode)
                    }
                }
                .pickerStyle(.menu)

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
            Toggle("Enable embedding similarity", isOn: $draftEmbeddingEnabled)
                .toggleStyle(.checkbox)
            TextField("Base URL", text: $draftEmbeddingBaseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("API key (leave blank to keep saved)", text: $draftEmbeddingAPIKey)
                .textFieldStyle(.roundedBorder)
            TextField("Model", text: $draftEmbeddingModel)
                .textFieldStyle(.roundedBorder)
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

                TextField("Prompt title", text: $newPromptTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $newPromptContent)
                    .font(.paperCodexSystem(size: 13))
                    .frame(minHeight: 78)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("New quick prompt editor")
                    .accessibilityValue("\(newPromptContent.count) characters")
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
            Picker("Folder rule", selection: Binding(
                get: { model.arxivSaveOrganization },
                set: { model.setArxivSaveOrganization($0) }
            )) {
                ForEach(ArxivSaveOrganization.allCases) { option in
                    Text(LocalizedStringKey(option.title)).tag(option)
                }
            }
            .pickerStyle(.radioGroup)

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
                    isConfirmingClearCache = true
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
            TextEditor(text: $draftCodexSystemPrompt)
                .font(.paperCodexSystem(size: 13, design: .monospaced))
                .frame(minHeight: 320)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("System prompt template editor")
                .accessibilityValue("\(draftCodexSystemPrompt.count) characters")
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
            TextField("Prompt title", text: $editingPromptTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $editingPromptContent)
                .font(.paperCodexSystem(size: 13))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Quick prompt editor")
                .accessibilityValue("\(editingPromptContent.count) characters")
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

private struct SettingsCategoryToggleRow: View {
    @State private var isHovering = false

    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.paperCodexSystem(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsSelectableRowButtonStyle(selected: selected, isHovering: isHovering))
        .onHover { hovering in
            withAnimation(PaperCodexMotion.hover) {
                isHovering = hovering
            }
        }
    }
}

private struct SettingsSelectableRowButtonStyle: ButtonStyle {
    var selected: Bool
    var isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .foregroundStyle(labelColor(isPressed: isPressed))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor(isPressed: isPressed), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.985 : (isHovering ? 1.01 : 1), anchor: .center)
            .animation(PaperCodexMotion.press, value: configuration.isPressed)
            .animation(PaperCodexMotion.hover, value: isHovering)
            .animation(PaperCodexMotion.selection, value: selected)
    }

    private func labelColor(isPressed: Bool) -> Color {
        if selected || isPressed || isHovering {
            return Color.primary.opacity(0.92)
        }
        return Color.primary.opacity(0.82)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.16)
        }
        if selected {
            return Color.accentColor.opacity(0.10)
        }
        return isHovering ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.44)
        }
        if selected {
            return Color.accentColor.opacity(0.26)
        }
        return isHovering ? Color.accentColor.opacity(0.22) : Color.clear
    }
}

private struct SettingsActionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var systemImage: String?
    var kind: SettingsActionButtonKind = .secondary
    var disabled = false
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        NativeSettingsActionButton(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            role: role,
            reduceMotion: reduceMotion,
            action: action
        )
        .fixedSize(horizontal: true, vertical: true)
        .help(title)
    }
}

private struct NativeSettingsActionButton: NSViewRepresentable {
    var title: String
    var systemImage: String?
    var kind: SettingsActionButtonKind
    var disabled: Bool
    var role: ButtonRole?
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativeSettingsActionButtonView {
        let view = NativeSettingsActionButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            role: role,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativeSettingsActionButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            role: role,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private final class NativeSettingsActionButtonView: NSButton {
    private enum Metrics {
        static let height: CGFloat = max(
            PaperCodexHitTarget.toolbarButtonHeight,
            PaperCodexHitTarget.toolbarButtonFontSize + PaperCodexHitTarget.toolbarButtonVerticalPadding * 2
        )
        static let iconSize: CGFloat = PaperCodexHitTarget.toolbarButtonSymbolSize
        static let iconWidth: CGFloat = PaperCodexHitTarget.toolbarButtonSymbolWidth
        static let iconTextSpacing: CGFloat = PaperCodexHitTarget.toolbarButtonSymbolTextSpacing
        static let horizontalPadding: CGFloat = PaperCodexHitTarget.toolbarButtonHorizontalPadding
        static let fontSize: CGFloat = PaperCodexHitTarget.toolbarButtonFontSize
        static let cornerRadius: CGFloat = PaperCodexCornerRadius.control
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var titleLeadingIconConstraint: NSLayoutConstraint?
    private var titleLeadingButtonConstraint: NSLayoutConstraint?
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var kind = SettingsActionButtonKind.secondary
    private var hasIcon = false
    private var isHovering = false
    private var isPressed = false
    private var isDisabled = false
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
        let iconWidth = hasIcon ? Metrics.iconWidth + Metrics.iconTextSpacing : 0
        let width = Metrics.horizontalPadding * 2 + iconWidth + titleLabel.intrinsicContentSize.width
        return NSSize(width: ceil(width), height: Metrics.height)
    }

    func apply(
        title: String,
        systemImage: String?,
        kind: SettingsActionButtonKind,
        disabled: Bool,
        role: ButtonRole?,
        reduceMotion: Bool,
        action: @escaping () -> Void
    ) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        self.kind = role == .destructive ? .destructive : kind
        isDisabled = disabled
        self.reduceMotion = reduceMotion
        isEnabled = !disabled
        hasIcon = systemImage != nil
        titleLabel.stringValue = localizedTitle
        iconView.image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: localizedTitle) }
        iconView.isHidden = systemImage == nil
        titleLeadingIconConstraint?.isActive = systemImage != nil
        titleLeadingButtonConstraint?.isActive = systemImage == nil
        toolTip = localizedTitle
        setAccessibilityLabel(localizedTitle)
        invalidateIntrinsicContentSize()
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
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard !isDisabled else {
            return
        }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.momentaryChange)
        target = self
        action = #selector(performPress)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Metrics.iconSize, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: Metrics.fontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        [iconView, titleLabel].forEach(addSubview(_:))
        let leadingIconConstraint = titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.iconTextSpacing)
        let leadingButtonConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding)
        titleLeadingIconConstraint = leadingIconConstraint
        titleLeadingButtonConstraint = leadingButtonConstraint
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.height),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconWidth),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconWidth),
            leadingIconConstraint,
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        guard !isDisabled else {
            return
        }
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = NSColor(kind.tint)
        let foreground: NSColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isDisabled {
            foreground = .secondaryLabelColor.withAlphaComponent(0.48)
            background = .controlBackgroundColor.withAlphaComponent(0.56)
            border = .black.withAlphaComponent(0.06)
            shadowOpacity = 0
        } else {
            switch kind {
            case .primary:
                foreground = .white
                background = tint.withAlphaComponent(isPressed ? 0.82 : (isHovering ? 0.96 : 0.90))
                border = tint.withAlphaComponent(isPressed ? 0.62 : (isHovering ? 0.48 : 0.34))
                shadowOpacity = isPressed ? 0.10 : (isHovering ? 0.16 : 0)
            case .secondary, .destructive:
                foreground = isPressed || isHovering ? tint : .labelColor.withAlphaComponent(0.82)
                background = isPressed ? tint.withAlphaComponent(0.18) : (isHovering ? tint.withAlphaComponent(0.12) : .controlBackgroundColor)
                border = isPressed ? tint.withAlphaComponent(0.54) : (isHovering ? tint.withAlphaComponent(0.38) : .black.withAlphaComponent(0.10))
                shadowOpacity = isPressed ? 0.10 : (isHovering ? 0.16 : 0)
            }
        }

        iconView.contentTintColor = foreground
        titleLabel.textColor = foreground
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 3 : 7
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -3)

        let targetScale: CGFloat
        if reduceMotion || isDisabled {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.97
        } else {
            targetScale = isHovering ? 1.02 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
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
