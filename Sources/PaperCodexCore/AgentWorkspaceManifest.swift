import Foundation

public enum WorkspaceMaterializationMode: String, Codable, CaseIterable, Sendable {
    case copyPDF = "copy-pdf"
    case symlinkPDF = "symlink-pdf"
}

public struct AgentWorkspacePaper: Codable, Equatable, Identifiable, Sendable {
    public var id: String { paperID }
    public var paperID: String
    public var title: String
    public var originalPDFPath: String
    public var fullTextPath: String
    public var pagesJSONLPath: String
    public var spansJSONLPath: String
    public var anchorsJSONLPath: String
    public var metadataJSONPath: String

    public init(
        paperID: String,
        title: String,
        originalPDFPath: String,
        fullTextPath: String,
        pagesJSONLPath: String,
        spansJSONLPath: String,
        anchorsJSONLPath: String,
        metadataJSONPath: String
    ) {
        self.paperID = paperID
        self.title = title
        self.originalPDFPath = originalPDFPath
        self.fullTextPath = fullTextPath
        self.pagesJSONLPath = pagesJSONLPath
        self.spansJSONLPath = spansJSONLPath
        self.anchorsJSONLPath = anchorsJSONLPath
        self.metadataJSONPath = metadataJSONPath
    }
}

public struct AgentWorkspaceManifest: Codable, Equatable, Sendable {
    public var sessionID: String
    public var workspacePath: String
    public var materializationMode: WorkspaceMaterializationMode
    public var mcpConfigPath: String?
    public var promptContractPath: String
    public var agentInstructionsPath: String
    public var papers: [AgentWorkspacePaper]

    public init(
        sessionID: String,
        workspacePath: String,
        materializationMode: WorkspaceMaterializationMode,
        mcpConfigPath: String?,
        promptContractPath: String,
        agentInstructionsPath: String,
        papers: [AgentWorkspacePaper]
    ) {
        self.sessionID = sessionID
        self.workspacePath = workspacePath
        self.materializationMode = materializationMode
        self.mcpConfigPath = mcpConfigPath
        self.promptContractPath = promptContractPath
        self.agentInstructionsPath = agentInstructionsPath
        self.papers = papers
    }
}
