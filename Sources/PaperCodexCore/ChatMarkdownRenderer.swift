import Foundation

public struct ChatMarkdownRenderStyle: Equatable, Sendable {
    public var fontSize: Double
    public var fontFamily: String

    public init(
        fontSize: Double = 16,
        fontFamily: String = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
    ) {
        self.fontSize = min(max(fontSize, 11), 28)
        self.fontFamily = Self.sanitizedFontFamily(fontFamily)
    }

    private static func sanitizedFontFamily(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "\n\r;{}<>")
        let sanitized = value.components(separatedBy: disallowed).joined(separator: " ")
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif" : trimmed
    }
}

public enum ChatMarkdownRenderer {
    public static func renderDocument(
        markdown: String,
        style: ChatMarkdownRenderStyle = ChatMarkdownRenderStyle()
    ) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
          color-scheme: light dark;
          font: -apple-system-body;
        }
        body {
          margin: 0;
          background: transparent;
          color: CanvasText;
          overflow-wrap: anywhere;
        }
        html, body, .message {
          width: 100%;
          box-sizing: border-box;
        }
        .message {
          font-family: \(style.fontFamily);
          font-size: \(formattedFontSize(style.fontSize))px;
          line-height: 1.55;
          max-width: none;
        }
        p, ul, ol, blockquote, pre, table {
          margin: 0 0 0.72em;
        }
        h1, h2, h3 {
          margin: 0.25em 0 0.45em;
          line-height: 1.2;
        }
        h1 { font-size: 1.35em; }
        h2 { font-size: 1.18em; }
        h3 { font-size: 1.05em; }
        a {
          color: LinkText;
        }
        a.citation {
          display: inline-flex;
          align-items: center;
          min-width: 1.6em;
          height: 1.45em;
          padding: 0 0.35em;
          border-radius: 0.72em;
          background: color-mix(in srgb, LinkText 16%, transparent);
          color: LinkText;
          font-size: 0.86em;
          font-weight: 650;
          text-decoration: none;
          vertical-align: 0.08em;
        }
        code {
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 0.92em;
          background: color-mix(in srgb, CanvasText 8%, transparent);
          border-radius: 4px;
          padding: 0.08em 0.28em;
        }
        pre {
          overflow-x: auto;
          padding: 0.7em;
          border-radius: 6px;
          background: color-mix(in srgb, CanvasText 8%, transparent);
        }
        pre code {
          background: transparent;
          padding: 0;
        }
        blockquote {
          padding-left: 0.8em;
          border-left: 3px solid color-mix(in srgb, CanvasText 24%, transparent);
          color: color-mix(in srgb, CanvasText 78%, transparent);
        }
        table {
          border-collapse: collapse;
          width: 100%;
        }
        th, td {
          border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
          padding: 0.35em 0.5em;
          text-align: left;
        }
        img {
          max-width: 100%;
          height: auto;
          border-radius: 6px;
        }
        .math-display {
          margin: 0 0 0.72em;
          overflow-x: auto;
        }
        .katex {
          font-size: 1.03em;
        }
        .katex-display {
          margin: 0.2em 0;
          overflow-x: auto;
          overflow-y: hidden;
          max-width: 100%;
        }
        </style>
        <link rel="stylesheet" href="KaTeX/katex.min.css">
        <script defer src="KaTeX/katex.min.js"></script>
        <script defer src="KaTeX/contrib/auto-render.min.js"></script>
        </head>
        <body>
        <div class="message">
        \(renderFragment(markdown: markdown))
        </div>
        <script>
        function reportHeight() {
          const height = Math.ceil(document.documentElement.scrollHeight);
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.height) {
            window.webkit.messageHandlers.height.postMessage(height);
          }
        }
        let didRenderMath = false;
        function renderMath() {
          if (didRenderMath || !window.renderMathInElement) {
            return;
          }
          didRenderMath = true;
          renderMathInElement(document.querySelector('.message'), {
            delimiters: [
              {left: '$$', right: '$$', display: true},
              {left: '\\\\[', right: '\\\\]', display: true},
              {left: '\\\\(', right: '\\\\)', display: false},
              {left: '$', right: '$', display: false}
            ],
            ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
            throwOnError: false,
            strict: 'ignore'
          });
          reportHeight();
          setTimeout(reportHeight, 50);
        }
        document.addEventListener('DOMContentLoaded', renderMath);
        window.addEventListener('load', function() {
          renderMath();
          reportHeight();
        });
        window.addEventListener('resize', reportHeight);
        setTimeout(function() { renderMath(); reportHeight(); }, 50);
        setTimeout(function() { renderMath(); reportHeight(); }, 250);
        setTimeout(function() { renderMath(); reportHeight(); }, 1000);
        </script>
        </body>
        </html>
        """
    }

    private static func formattedFontSize(_ size: Double) -> String {
        if size.rounded() == size {
            return String(Int(size))
        }
        return String(format: "%.1f", size)
    }

    public static func renderFragment(markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var html: [String] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var orderedListItems: [String] = []
        var codeLines: [String] = []
        var inCode = false
        var displayMathLines: [String] = []
        var displayMathOpeningDelimiter: String?
        var displayMathClosingDelimiter: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else {
                return
            }
            html.append("<p>\(renderInline(paragraph.joined(separator: "\n")))</p>")
            paragraph.removeAll()
        }

        func flushLists() {
            if !listItems.isEmpty {
                html.append("<ul>\(listItems.map { "<li>\($0)</li>" }.joined())</ul>")
                listItems.removeAll()
            }
            if !orderedListItems.isEmpty {
                html.append("<ol>\(orderedListItems.map { "<li>\($0)</li>" }.joined())</ol>")
                orderedListItems.removeAll()
            }
        }

        func flushCode() {
            guard !codeLines.isEmpty else {
                return
            }
            html.append("<pre><code>\(escapeText(codeLines.joined(separator: "\n")))</code></pre>")
            codeLines.removeAll()
        }

        func resetDisplayMath() {
            displayMathLines.removeAll()
            displayMathOpeningDelimiter = nil
            displayMathClosingDelimiter = nil
        }

        func flushDisplayMath(closedBy closing: String) {
            guard let opening = displayMathOpeningDelimiter,
                  displayMathClosingDelimiter != nil else {
                return
            }
            let block = ([opening] + displayMathLines + [closing]).joined(separator: "\n")
            html.append(#"<div class="math-display">\#(escapeText(block))</div>"#)
            resetDisplayMath()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushLists()
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    inCode = true
                }
                index += 1
                continue
            }

            if inCode {
                codeLines.append(line)
                index += 1
                continue
            }

            if let closing = displayMathClosingDelimiter {
                if trimmed == closing {
                    flushDisplayMath(closedBy: closing)
                } else {
                    displayMathLines.append(line)
                }
                index += 1
                continue
            }

            if let delimiter = displayMathDelimiter(for: trimmed) {
                flushParagraph()
                flushLists()
                displayMathOpeningDelimiter = delimiter.opening
                displayMathClosingDelimiter = delimiter.closing
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushLists()
                index += 1
                continue
            }

            if isTableStart(lines: lines, index: index) {
                flushParagraph()
                flushLists()
                let rendered = renderTable(lines: lines, start: index)
                html.append(rendered.html)
                index = rendered.nextIndex
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                flushLists()
                html.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                flushLists()
                html.append("<blockquote>\(renderInline(String(trimmed.dropFirst(2))))</blockquote>")
                index += 1
                continue
            }

            if let unordered = parseUnorderedListItem(trimmed) {
                flushParagraph()
                if !orderedListItems.isEmpty {
                    html.append("<ol>\(orderedListItems.map { "<li>\($0)</li>" }.joined())</ol>")
                    orderedListItems.removeAll()
                }
                listItems.append(renderInline(unordered))
                index += 1
                continue
            }

            if let ordered = parseOrderedListItem(trimmed) {
                flushParagraph()
                if !listItems.isEmpty {
                    html.append("<ul>\(listItems.map { "<li>\($0)</li>" }.joined())</ul>")
                    listItems.removeAll()
                }
                orderedListItems.append(renderInline(ordered))
                index += 1
                continue
            }

            paragraph.append(line)
            index += 1
        }

        if inCode {
            flushCode()
        }
        if let opening = displayMathOpeningDelimiter {
            paragraph.append(opening)
            paragraph.append(contentsOf: displayMathLines)
            resetDisplayMath()
        }
        flushParagraph()
        flushLists()
        return html.joined(separator: "\n")
    }

    private static func renderInline(_ text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            if let mathEnd = inlineDoubleDollarMathEnd(in: text, openingAt: index) {
                let contentStart = text.index(index, offsetBy: 2)
                let content = String(text[contentStart..<mathEnd])
                output.append("\\(\(escapeText(content))\\)")
                index = text.index(mathEnd, offsetBy: 2)
                continue
            }

            if let mathEnd = inlineMathEnd(in: text, openingAt: index) {
                output.append(escapeText(String(text[index...mathEnd])))
                index = text.index(after: mathEnd)
                continue
            }

            if text[index...].hasPrefix("!["),
               let link = parseInlineLink(in: text, labelStart: text.index(index, offsetBy: 2)) {
                let alt = String(text[text.index(index, offsetBy: 2)..<link.labelEnd])
                let source = String(text[link.destinationStart..<link.destinationEnd])
                output.append(#"<img alt="\#(escapeAttribute(alt))" src="\#(escapeAttribute(normalizeImageSource(source)))">"#)
                index = text.index(after: link.destinationEnd)
                continue
            }

            if text[index] == "[",
               let link = parseInlineLink(in: text, labelStart: text.index(after: index)) {
                let label = String(text[text.index(after: index)..<link.labelEnd])
                let href = String(text[link.destinationStart..<link.destinationEnd])
                let className = href.hasPrefix("papercodex-cite://") ? #" class="citation""# : ""
                output.append(#"<a\#(className) href="\#(escapeAttribute(href))">\#(renderInline(label))</a>"#)
                index = text.index(after: link.destinationEnd)
                continue
            }

            if text[index] == "`",
               let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let code = String(text[text.index(after: index)..<end])
                output.append("<code>\(escapeText(code))</code>")
                index = text.index(after: end)
                continue
            }

            if text[index...].hasPrefix("**"),
               let end = text[text.index(index, offsetBy: 2)...].range(of: "**")?.lowerBound {
                let content = String(text[text.index(index, offsetBy: 2)..<end])
                output.append("<strong>\(renderInline(content))</strong>")
                index = text.index(end, offsetBy: 2)
                continue
            }

            if text[index] == "*",
               let end = text[text.index(after: index)...].firstIndex(of: "*") {
                let content = String(text[text.index(after: index)..<end])
                output.append("<em>\(renderInline(content))</em>")
                index = text.index(after: end)
                continue
            }

            output.append(escapeText(String(text[index])))
            index = text.index(after: index)
        }

        return output.replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func inlineDoubleDollarMathEnd(in text: String, openingAt index: String.Index) -> String.Index? {
        guard text[index...].hasPrefix("$$") else {
            return nil
        }
        let afterOpening = text.index(index, offsetBy: 2)
        guard afterOpening < text.endIndex else {
            return nil
        }
        return text[afterOpening...].range(of: "$$")?.lowerBound
    }

    private static func inlineMathEnd(in text: String, openingAt index: String.Index) -> String.Index? {
        if text[index] == "$" {
            let afterOpening = text.index(after: index)
            guard afterOpening < text.endIndex, text[afterOpening] != "$" else {
                return nil
            }
            return text[afterOpening...].firstIndex(of: "$")
        }

        if text[index...].hasPrefix("\\(") {
            let afterOpening = text.index(index, offsetBy: 2)
            guard let closingStart = text[afterOpening...].range(of: "\\)")?.lowerBound else {
                return nil
            }
            return text.index(after: closingStart)
        }

        if text[index...].hasPrefix("\\[") {
            let afterOpening = text.index(index, offsetBy: 2)
            guard let closingStart = text[afterOpening...].range(of: "\\]")?.lowerBound else {
                return nil
            }
            return text.index(after: closingStart)
        }

        return nil
    }

    private static func parseInlineLink(
        in text: String,
        labelStart: String.Index
    ) -> (labelEnd: String.Index, destinationStart: String.Index, destinationEnd: String.Index)? {
        guard let labelEnd = inlineLinkLabelEnd(in: text, start: labelStart) else {
            return nil
        }
        let openParen = text.index(after: labelEnd)
        guard openParen < text.endIndex, text[openParen] == "(" else {
            return nil
        }
        let destinationStart = text.index(after: openParen)
        guard let destinationEnd = inlineLinkDestinationEnd(in: text, start: destinationStart) else {
            return nil
        }
        return (labelEnd, destinationStart, destinationEnd)
    }

    private static func inlineLinkLabelEnd(in text: String, start: String.Index) -> String.Index? {
        var index = start
        var bracketDepth = 0

        while index < text.endIndex {
            if text[index] == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else {
                    return nil
                }
                index = text.index(after: next)
                continue
            }

            if text[index] == "[" {
                bracketDepth += 1
            } else if text[index] == "]" {
                if bracketDepth == 0 {
                    return index
                }
                bracketDepth -= 1
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func inlineLinkDestinationEnd(in text: String, start: String.Index) -> String.Index? {
        var index = start
        var parenthesisDepth = 0

        while index < text.endIndex {
            if text[index] == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else {
                    return nil
                }
                index = text.index(after: next)
                continue
            }

            if text[index] == "(" {
                parenthesisDepth += 1
            } else if text[index] == ")" {
                if parenthesisDepth == 0 {
                    return index
                }
                parenthesisDepth -= 1
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard markerCount > 0, markerCount <= 3 else {
            return nil
        }
        let textStart = line.index(line.startIndex, offsetBy: markerCount)
        guard textStart < line.endIndex, line[textStart] == " " else {
            return nil
        }
        return (markerCount, String(line[line.index(after: textStart)...]))
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        for marker in ["- ", "* "] {
            if line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count))
            }
        }
        return nil
    }

    private static func parseOrderedListItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else {
            return nil
        }
        let prefix = line[..<dot]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else {
            return nil
        }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else {
            return nil
        }
        return String(line[line.index(after: afterDot)...])
    }

    private static func displayMathDelimiter(for line: String) -> (opening: String, closing: String)? {
        switch line {
        case "$$":
            return ("$$", "$$")
        case "\\[":
            return ("\\[", "\\]")
        default:
            return nil
        }
    }

    private static func isTableStart(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else {
            return false
        }
        return lines[index].contains("|") && isTableSeparator(lines[index + 1])
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return false
        }
        let stripped = trimmed.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty
    }

    private static func renderTable(lines: [String], start: Int) -> (html: String, nextIndex: Int) {
        let headers = splitTableRow(lines[start])
        var index = start + 2
        var rows: [[String]] = []
        while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            rows.append(splitTableRow(lines[index]))
            index += 1
        }
        let headerHTML = headers.map { "<th>\(renderInline($0))</th>" }.joined()
        let bodyHTML = rows.map { row in
            "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>"
        }.joined()
        return ("<table><thead><tr>\(headerHTML)</tr></thead><tbody>\(bodyHTML)</tbody></table>", index)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|"), !isEscapedPipe(at: trimmed.index(before: trimmed.endIndex), in: trimmed) {
            trimmed.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var index = trimmed.startIndex
        var inCode = false
        var inDollarMath = false
        var inParenMath = false
        var inBracketMath = false

        while index < trimmed.endIndex {
            if trimmed[index] == "\\" {
                let next = trimmed.index(after: index)
                if next < trimmed.endIndex {
                    if inParenMath, trimmed[next] == ")" {
                        current.append("\\)")
                        inParenMath = false
                        index = trimmed.index(after: next)
                        continue
                    }
                    if inBracketMath, trimmed[next] == "]" {
                        current.append("\\]")
                        inBracketMath = false
                        index = trimmed.index(after: next)
                        continue
                    }
                    if !inCode, !inDollarMath, !inParenMath, !inBracketMath, trimmed[next] == "(" {
                        current.append("\\(")
                        inParenMath = true
                        index = trimmed.index(after: next)
                        continue
                    }
                    if !inCode, !inDollarMath, !inParenMath, !inBracketMath, trimmed[next] == "[" {
                        current.append("\\[")
                        inBracketMath = true
                        index = trimmed.index(after: next)
                        continue
                    }
                    if !inCode, !inDollarMath, !inParenMath, !inBracketMath, trimmed[next] == "|" {
                        current.append("|")
                        index = trimmed.index(after: next)
                        continue
                    }
                }
            }

            let character = trimmed[index]
            if !inDollarMath, !inParenMath, !inBracketMath, character == "`" {
                inCode.toggle()
                current.append(character)
                index = trimmed.index(after: index)
                continue
            }

            if !inCode, !inParenMath, !inBracketMath, character == "$" {
                let next = trimmed.index(after: index)
                if next < trimmed.endIndex, trimmed[next] == "$" {
                    current.append(character)
                } else {
                    inDollarMath.toggle()
                    current.append(character)
                }
                index = next
                continue
            }

            if !inCode, !inDollarMath, !inParenMath, !inBracketMath, character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll()
            } else {
                current.append(character)
            }
            index = trimmed.index(after: index)
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isEscapedPipe(at index: String.Index, in text: String) -> Bool {
        guard text[index] == "|" else {
            return false
        }
        var backslashCount = 0
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            guard text[previous] == "\\" else {
                break
            }
            backslashCount += 1
            cursor = previous
        }
        return backslashCount % 2 == 1
    }

    private static func normalizeImageSource(_ source: String) -> String {
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source).absoluteString
        }
        return source
    }

    private static func escapeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeText(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
