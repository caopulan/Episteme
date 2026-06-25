import Foundation

public enum ACPAgentRuntimeAdapterError: Error, CustomStringConvertible, Equatable {
    case missingServerArguments(String)

    public var description: String {
        switch self {
        case let .missingServerArguments(runtimeID):
            "ACP runtime \(runtimeID) does not define server arguments"
        }
    }
}

public struct ACPAgentRuntimeAdapter: Sendable {
    public var executablePath: String
    public var profile: AgentRuntimeProfile

    public init(executablePath: String, profile: AgentRuntimeProfile) {
        self.executablePath = executablePath
        self.profile = profile
    }

    public static func findExecutable(
        for profile: AgentRuntimeProfile,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> String {
        try AgentRuntimeExecutableResolver.executablePath(
            named: profile.executableName,
            additionalPaths: profile.knownExecutablePaths,
            environment: environment,
            fileManager: fileManager
        )
    }

    public func serverCommand(
        workspacePath: String,
        environmentOverrides: [String: String] = [:]
    ) -> AgentRuntimeCommand {
        AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: profile.acpServerArguments,
            currentDirectoryPath: workspacePath,
            environmentOverrides: environmentOverrides
        )
    }
}
