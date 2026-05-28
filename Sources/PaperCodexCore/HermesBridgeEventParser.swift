import Foundation

public struct HermesBridgeParsedLine: Equatable, Sendable {
    public var event: CodexRunEvent?
    public var finalAnswer: String?
    public var sessionID: String?

    public init(event: CodexRunEvent?, finalAnswer: String?, sessionID: String?) {
        self.event = event
        self.finalAnswer = finalAnswer
        self.sessionID = sessionID
    }
}

public enum HermesBridgeEventParser {
    public static func parseLine(_ line: String) throws -> CodexRunEvent? {
        try parseResultLine(line).event
    }

    public static func parseResultLine(_ line: String) throws -> HermesBridgeParsedLine {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return HermesBridgeParsedLine(event: nil, finalAnswer: nil, sessionID: nil)
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HermesBridgeParsedLine(
                event: CodexRunEvent(kind: .raw, title: "Hermes", detail: trimmed),
                finalAnswer: nil,
                sessionID: nil
            )
        }

        let type = stringValue(named: "type", in: json) ?? "event"
        switch type {
        case "tool":
            let name = stringValue(named: "name", in: json)
                ?? stringValue(named: "title", in: json)
                ?? "Hermes tool"
            let detail = toolDetail(in: json)
            return HermesBridgeParsedLine(
                event: CodexRunEvent(kind: .tool, title: name, detail: detail),
                finalAnswer: nil,
                sessionID: nil
            )
        case "answer":
            let text = stringValue(named: "text", in: json) ?? ""
            return HermesBridgeParsedLine(
                event: CodexRunEvent(kind: .answer, title: "Final answer", detail: text),
                finalAnswer: text,
                sessionID: nil
            )
        case "session":
            let sessionID = stringValue(named: "session_id", in: json)
            let detail = sessionID.map { "Hermes session \($0)" } ?? "Hermes session updated"
            return HermesBridgeParsedLine(
                event: CodexRunEvent(kind: .status, title: "Session", detail: detail),
                finalAnswer: nil,
                sessionID: sessionID
            )
        case "status":
            let title = stringValue(named: "title", in: json) ?? "Hermes"
            let detail = stringValue(named: "detail", in: json)
                ?? stringValue(named: "message", in: json)
                ?? title
            return HermesBridgeParsedLine(
                event: CodexRunEvent(kind: .status, title: title, detail: detail),
                finalAnswer: nil,
                sessionID: nil
            )
        case "warning":
            let detail = stringValue(named: "detail", in: json)
                ?? stringValue(named: "message", in: json)
                ?? "Hermes warning"
            return HermesBridgeParsedLine(
                event: CodexRunEvent(kind: .warning, title: "Hermes warning", detail: detail),
                finalAnswer: nil,
                sessionID: nil
            )
        case "error":
            let detail = stringValue(named: "detail", in: json)
                ?? stringValue(named: "message", in: json)
                ?? "Hermes error"
            return HermesBridgeParsedLine(
                event: CodexRunEvent(kind: .error, title: "Hermes error", detail: detail),
                finalAnswer: nil,
                sessionID: nil
            )
        default:
            return HermesBridgeParsedLine(
                event: CodexRunEvent(kind: .raw, title: type, detail: compactJSONString(json) ?? trimmed),
                finalAnswer: nil,
                sessionID: nil
            )
        }
    }

    private static func toolDetail(in json: [String: Any]) -> String {
        if let detail = stringValue(named: "detail", in: json) {
            return detail
        }
        if let preview = stringValue(named: "preview", in: json) {
            return preview
        }
        let state = stringValue(named: "state", in: json)
        if state == "completed" {
            let duration = doubleValue(named: "duration", in: json)
            let base = duration.map { String(format: "Completed in %.2fs", $0) } ?? "Completed"
            return boolValue(named: "is_error", in: json) == true ? "\(base) with error" : base
        }
        if state == "started" {
            return "Running"
        }
        return state ?? "Tool update"
    }

    private static func stringValue(named key: String, in value: Any?) -> String? {
        guard let dictionary = value as? [String: Any],
              let raw = dictionary[key] else {
            return nil
        }
        if let string = raw as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private static func doubleValue(named key: String, in value: Any?) -> Double? {
        guard let dictionary = value as? [String: Any],
              let raw = dictionary[key] else {
            return nil
        }
        if let double = raw as? Double {
            return double
        }
        if let int = raw as? Int {
            return Double(int)
        }
        if let string = raw as? String {
            return Double(string)
        }
        return nil
    }

    private static func boolValue(named key: String, in value: Any?) -> Bool? {
        guard let dictionary = value as? [String: Any],
              let raw = dictionary[key] else {
            return nil
        }
        if let bool = raw as? Bool {
            return bool
        }
        if let string = raw as? String {
            return Bool(string)
        }
        return nil
    }

    private static func compactJSONString(_ value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
