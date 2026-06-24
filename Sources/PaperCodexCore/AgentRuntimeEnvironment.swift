import Foundation

public enum AgentRuntimeEnvironment {
    public static func sanitizedProcessEnvironment(
        workingDirectoryURL: URL? = nil,
        executablePath: String? = nil,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        environmentOverrides: [String: String] = [:]
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["PATH"] = enrichedPath(
            existingPath: environment["PATH"],
            executablePath: executablePath,
            environment: environment
        )
        if let workingDirectoryURL {
            environment["PWD"] = workingDirectoryURL.standardizedFileURL.path
        }
        environment.removeValue(forKey: "OLDPWD")
        for (key, value) in environmentOverrides {
            environment[key] = value
        }
        return environment
    }

    private static func enrichedPath(
        existingPath: String?,
        executablePath: String?,
        environment: [String: String]
    ) -> String {
        var candidates: [String] = []
        if let executablePath,
           !executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(URL(fileURLWithPath: executablePath).deletingLastPathComponent().path)
        }
        candidates += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "~/.local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].map { expandHome(in: $0, environment: environment) }
        candidates += (existingPath ?? "")
            .split(separator: ":")
            .map(String.init)

        var seen: Set<String> = []
        let uniqueCandidates = candidates.compactMap { candidate -> String? in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            guard !seen.contains(standardized) else {
                return nil
            }
            seen.insert(standardized)
            return standardized
        }
        return uniqueCandidates.joined(separator: ":")
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
