import Foundation

public struct ReaderPaperTab: Codable, Equatable, Identifiable, Sendable {
    public var id: String { paperID }
    public var paperID: String
    public var title: String
    public var detail: String
    public var isSaved: Bool

    public init(paperID: String, title: String, detail: String, isSaved: Bool) {
        self.paperID = paperID
        self.title = title
        self.detail = detail
        self.isSaved = isSaved
    }

    public init(paper: Paper) {
        self.init(
            paperID: paper.id,
            title: paper.title,
            detail: paper.filePath,
            isSaved: paper.isSaved
        )
    }
}

public struct ReaderTabState: Codable, Equatable, Sendable {
    public private(set) var tabs: [ReaderPaperTab]
    public private(set) var activePaperID: String?

    public init(tabs: [ReaderPaperTab] = [], activePaperID: String? = nil) {
        self.tabs = []
        self.activePaperID = nil
        for tab in tabs {
            open(tab)
        }
        if let activePaperID {
            _ = select(activePaperID)
        }
    }

    public mutating func open(_ tab: ReaderPaperTab) {
        if let index = tabs.firstIndex(where: { $0.paperID == tab.paperID }) {
            tabs[index] = tab
        } else {
            tabs.append(tab)
        }
        activePaperID = tab.paperID
    }

    @discardableResult
    public mutating func select(_ paperID: String) -> String? {
        guard tabs.contains(where: { $0.paperID == paperID }) else {
            return activePaperID
        }
        activePaperID = paperID
        return activePaperID
    }

    public func adjacentPaperID(from paperID: String? = nil, offset: Int) -> String? {
        guard !tabs.isEmpty else {
            return nil
        }
        let currentPaperID = paperID ?? activePaperID ?? tabs[0].paperID
        guard let currentIndex = tabs.firstIndex(where: { $0.paperID == currentPaperID }) else {
            return tabs[0].paperID
        }
        guard offset != 0 else {
            return tabs[currentIndex].paperID
        }
        let nextIndex = (currentIndex + offset).positiveModulo(tabs.count)
        return tabs[nextIndex].paperID
    }

    @discardableResult
    public mutating func close(_ paperID: String) -> String? {
        guard let index = tabs.firstIndex(where: { $0.paperID == paperID }) else {
            return activePaperID
        }
        let wasActive = activePaperID == paperID
        tabs.remove(at: index)
        if tabs.isEmpty {
            activePaperID = nil
            return nil
        }
        if wasActive {
            let replacementIndex = min(index, tabs.count - 1)
            activePaperID = tabs[replacementIndex].paperID
        }
        return activePaperID
    }

    public mutating func replace(_ paperID: String, with tab: ReaderPaperTab) {
        tabs.removeAll { $0.paperID == tab.paperID && $0.paperID != paperID }
        if let index = tabs.firstIndex(where: { $0.paperID == paperID }) {
            tabs[index] = tab
        } else {
            tabs.append(tab)
        }
        if activePaperID == paperID || activePaperID == nil {
            activePaperID = tab.paperID
        }
    }

    public mutating func clearActivePaper() {
        activePaperID = nil
    }
}

private extension Int {
    func positiveModulo(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
