import Foundation

public enum AgentRuntimeLaunchMode: String, Codable, Sendable {
    case nonInteractive = "non-interactive"
    case pty
}

public struct AgentRuntimeCommand: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]
    public var currentDirectoryPath: String?
    public var environmentOverrides: [String: String]
    public var launchMode: AgentRuntimeLaunchMode

    public init(
        executablePath: String,
        arguments: [String],
        currentDirectoryPath: String? = nil,
        environmentOverrides: [String: String] = [:],
        launchMode: AgentRuntimeLaunchMode = .nonInteractive
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.currentDirectoryPath = currentDirectoryPath
        self.environmentOverrides = environmentOverrides
        self.launchMode = launchMode
    }
}
