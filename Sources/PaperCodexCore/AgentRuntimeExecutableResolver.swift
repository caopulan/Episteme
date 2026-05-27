import Foundation

public enum AgentRuntimeExecutableResolverError: Error, CustomStringConvertible, Equatable {
    case executableNotFound(String)

    public var description: String {
        switch self {
        case let .executableNotFound(name):
            "Could not find the \(name) executable in PATH"
        }
    }
}

public enum AgentRuntimeExecutableResolver {
    public static func executablePath(
        named executableName: String,
        additionalPaths: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> String {
        let pathValue = environment["PATH"] ?? ""
        let pathCandidates = pathValue
            .split(separator: ":")
            .map { String($0) + "/\(executableName)" }
        let homeExpandedPaths = additionalPaths.map { expandHome(in: $0, environment: environment) }
        var seen: Set<String> = []
        for candidate in pathCandidates + homeExpandedPaths {
            let standardized = URL(fileURLWithPath: candidate).standardizedFileURL.path
            guard !seen.contains(standardized) else {
                continue
            }
            seen.insert(standardized)
            if fileManager.isExecutableFile(atPath: standardized) {
                return standardized
            }
        }
        throw AgentRuntimeExecutableResolverError.executableNotFound(executableName)
    }

    private static func expandHome(in path: String, environment: [String: String]) -> String {
        guard path.hasPrefix("~/") else {
            return path
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(String(path.dropFirst(2)))
            .path
    }
}
