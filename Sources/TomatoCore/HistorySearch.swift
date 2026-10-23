import Foundation

public enum HistorySearchKind: String, CaseIterable, Hashable, Sendable {
    case todo, note, focus, outcome
}

public enum HistorySearchSource: String, Sendable {
    case userRecord, aiSummary
}

public enum HistorySearchTarget: Hashable, Sendable {
    case todo(UUID)
    case note(UUID)
    case session(UUID)
    case work(WorkScope)
}

public struct HistorySearchFilters: Sendable, Equatable {
    public var kinds: Set<HistorySearchKind>
    public var fromDay: String?
    public var throughDay: String?

    public init(kinds: Set<HistorySearchKind> = Set(HistorySearchKind.allCases),
                fromDay: String? = nil, throughDay: String? = nil) {
        self.kinds = kinds
        self.fromDay = fromDay
        self.throughDay = throughDay
    }
}

public struct HistorySearchResult: Identifiable, Sendable {
    public let id: String
    public let target: HistorySearchTarget
    public let kind: HistorySearchKind
    public let day: String
    public let title: String
    public let excerpt: String
    public let sources: [HistorySearchSource]

    public init(id: String, target: HistorySearchTarget, kind: HistorySearchKind, day: String,
                title: String, excerpt: String, sources: [HistorySearchSource]) {
        self.id = id
        self.target = target
        self.kind = kind
        self.day = day
        self.title = title
        self.excerpt = excerpt
        self.sources = sources
    }
}

/// 仅从用户可见的历史文字建立快照；计时状态、活动采样、图片和配置都不进入索引。
public struct HistorySearchIndex: Sendable {
    private let groups: [SearchGroup]

    public init(data: AppData) {
        var firstIntervalDay: [UUID: (startedAt: Date, day: String)] = [:]
        for interval in data.intervals {
            if let current = firstIntervalDay[interval.sessionID] {
                if interval.startedAt < current.startedAt ||
                    (interval.startedAt == current.startedAt && interval.localDay < current.day) {
                    firstIntervalDay[interval.sessionID] = (interval.startedAt, interval.localDay)
                }
            } else {
                firstIntervalDay[interval.sessionID] = (interval.startedAt, interval.localDay)
            }
        }

        var builders: [String: SearchGroupBuilder] = [:]

        func append(_ document: SearchDocument, to groupID: String,
                    defaultTarget: HistorySearchTarget, title: String,
                    outcomeTarget: HistorySearchTarget? = nil) {
            if var group = builders[groupID] {
                group.documents.append(document)
                if group.title.isEmpty && !title.isEmpty { group.title = title }
                if group.outcomeTarget == nil { group.outcomeTarget = outcomeTarget }
                builders[groupID] = group
            } else {
                builders[groupID] = SearchGroupBuilder(id: groupID, defaultTarget: defaultTarget,
                                                       outcomeTarget: outcomeTarget, title: title,
                                                       documents: [document])
            }
        }

        for todo in data.todos where !todo.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let groupID = "todo:\(todo.id.uuidString.lowercased())"
            append(SearchDocument(kind: .todo, day: todo.localDay, source: .userRecord, text: todo.text),
                   to: groupID, defaultTarget: .todo(todo.id), title: Self.title(todo.text, fallback: "待办"))
        }

        for note in data.notes where !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let groupID = "note:\(note.id.uuidString.lowercased())"
            append(SearchDocument(kind: .note, day: note.dayKey(), source: .userRecord, text: note.text),
                   to: groupID, defaultTarget: .note(note.id), title: note.title)
        }

        let sessionsByID = Dictionary(data.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for session in data.sessions {
            guard let goal = session.goal?.trimmingCharacters(in: .whitespacesAndNewlines), !goal.isEmpty else { continue }
            let day = firstIntervalDay[session.id]?.day ?? LocalTime.dayKey(session.startedAt)
            let groupID = "session:\(session.id.uuidString.lowercased())"
            append(SearchDocument(kind: .focus, day: day, source: .userRecord, text: goal),
                   to: groupID, defaultTarget: .session(session.id), title: Self.title(goal, fallback: "专注目标"),
                   outcomeTarget: .work(.session(session.id)))
        }

        for record in data.workRecords {
            let groupID: String
            let scope: WorkScope
            let defaultTarget: HistorySearchTarget
            let outcomeTarget: HistorySearchTarget
            let fallbackTitle: String

            if let sessionID = record.sessionID {
                groupID = "session:\(sessionID.uuidString.lowercased())"
                scope = .session(sessionID)
                defaultTarget = .session(sessionID)
                outcomeTarget = .work(scope)
                fallbackTitle = sessionsByID[sessionID]?.goal.map { Self.title($0, fallback: "本轮成果") } ?? "本轮成果"
            } else {
                groupID = "work-day:\(record.id.uuidString.lowercased())"
                scope = .day(record.localDay)
                defaultTarget = .work(scope)
                outcomeTarget = defaultTarget
                fallbackTitle = "每日成果"
            }

            let userText = record.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userText.isEmpty {
                let sessionGoal = record.sessionID.flatMap { sessionsByID[$0]?.goal }
                let title = sessionGoal.map { Self.title($0, fallback: fallbackTitle) }
                    ?? Self.title(userText, fallback: fallbackTitle)
                append(SearchDocument(kind: .outcome, day: record.localDay, source: .userRecord, text: record.userText),
                       to: groupID, defaultTarget: defaultTarget, title: title, outcomeTarget: outcomeTarget)
            }

            let summaryText = record.summary?.content.markdown.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !summaryText.isEmpty {
                let sessionGoal = record.sessionID.flatMap { sessionsByID[$0]?.goal }
                let title = sessionGoal.map { Self.title($0, fallback: fallbackTitle) }
                    ?? (userText.isEmpty ? "AI 成果总结" : Self.title(userText, fallback: fallbackTitle))
                append(SearchDocument(kind: .outcome, day: record.localDay, source: .aiSummary, text: summaryText),
                       to: groupID, defaultTarget: defaultTarget, title: title, outcomeTarget: outcomeTarget)
            }
        }

        groups = builders.values.map(SearchGroup.init)
    }

    public func search(query: String, filters: HistorySearchFilters = HistorySearchFilters(),
                       offset: Int = 0, limit: Int = 50) -> [HistorySearchResult] {
        let terms = Array(Set(query.split(whereSeparator: \.isWhitespace).map(String.init))).sorted()
        guard !terms.isEmpty, !filters.kinds.isEmpty, limit > 0 else { return [] }

        var results: [HistorySearchResult] = []
        for group in groups {
            let eligible = group.documents.filter { document in
                filters.kinds.contains(document.kind) &&
                    filters.fromDay.map { document.day >= $0 } != false &&
                    filters.throughDay.map { document.day <= $0 } != false
            }
            guard !eligible.isEmpty,
                  terms.allSatisfy({ term in eligible.contains { Self.contains(term, in: $0.text) } }) else { continue }

            let matched = eligible.filter { document in terms.contains { Self.contains($0, in: document.text) } }
            let focusMatches = matched.filter { $0.kind == .focus }
            let outcomeMatches = matched.filter { $0.kind == .outcome }
            let day: String
            if let focusDay = focusMatches.map(\.day).sorted().first {
                day = focusDay
            } else if let outcomeDay = outcomeMatches.map(\.day).max() {
                day = outcomeDay
            } else {
                day = matched.map(\.day).max() ?? ""
            }

            let fragments = matched.compactMap { document -> (HistorySearchSource, String, String)? in
                guard let excerpt = Self.excerpt(document.text, matching: terms) else { return nil }
                return (document.source, document.day, excerpt)
            }
            let sources = Self.sourceOrder.filter { source in fragments.contains { $0.0 == source } }
            let excerpt = Self.combinedExcerpt(fragments, resultDay: day)
            let kind = focusMatches.isEmpty ? (matched.first?.kind ?? .outcome) : .focus
            let target = outcomeMatches.isEmpty ? group.defaultTarget : (group.outcomeTarget ?? group.defaultTarget)

            results.append(HistorySearchResult(id: group.id, target: target, kind: kind, day: day,
                                               title: group.title, excerpt: excerpt, sources: sources))
        }

        results.sort {
            if $0.day != $1.day { return $0.day > $1.day }
            return $0.id < $1.id
        }

        let lowerBound = min(max(0, offset), results.count)
        let upperBound = min(results.count, lowerBound + limit)
        return Array(results[lowerBound..<upperBound])
    }

    private static let sourceOrder: [HistorySearchSource] = [.userRecord, .aiSummary]

    private static func contains(_ term: String, in text: String) -> Bool {
        !term.isEmpty && text.range(of: term, options: [.caseInsensitive]) != nil
    }

    private static func title(_ text: String, fallback: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !line.isEmpty else { return fallback }
        return line.count > 64 ? String(line.prefix(63)) + "…" : line
    }

    private static func excerpt(_ text: String, matching terms: [String]) -> String? {
        let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }

        var windows: [Range<String.Index>] = []
        for term in terms {
            guard let match = compact.range(of: term, options: [.caseInsensitive]) else { continue }
            let start = compact.index(match.lowerBound, offsetBy: -52, limitedBy: compact.startIndex) ?? compact.startIndex
            let end = compact.index(match.upperBound, offsetBy: 88, limitedBy: compact.endIndex) ?? compact.endIndex
            windows.append(start..<end)
        }
        guard !windows.isEmpty else { return nil }

        windows.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for window in windows {
            if let last = merged.last, window.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, window.upperBound)
            } else if merged.count < 3 {
                merged.append(window)
            }
        }

        return merged.map { range in
            let prefix = range.lowerBound == compact.startIndex ? "" : "…"
            let suffix = range.upperBound == compact.endIndex ? "" : "…"
            return prefix + compact[range].trimmingCharacters(in: .whitespacesAndNewlines) + suffix
        }.joined(separator: " … ")
    }

    private static func combinedExcerpt(_ fragments: [(HistorySearchSource, String, String)], resultDay: String) -> String {
        var parts: [String] = []
        for source in sourceOrder {
            var seen = Set<String>()
            let snippets = fragments.compactMap { fragment -> String? in
                guard fragment.0 == source else { return nil }
                let dayPrefix = fragment.1 == resultDay ? "" : "（\(fragment.1)）"
                let value = dayPrefix + fragment.2
                return seen.insert(value).inserted ? value : nil
            }
            guard !snippets.isEmpty else { continue }
            let label = source == .userRecord ? "用户记录" : "AI 总结"
            parts.append("\(label)：" + snippets.joined(separator: "；"))
        }
        return parts.joined(separator: "\n")
    }
}

private struct SearchDocument: Sendable {
    let kind: HistorySearchKind
    let day: String
    let source: HistorySearchSource
    let text: String
}

private struct SearchGroupBuilder {
    let id: String
    let defaultTarget: HistorySearchTarget
    var outcomeTarget: HistorySearchTarget?
    var title: String
    var documents: [SearchDocument]
}

private struct SearchGroup: Sendable {
    let id: String
    let defaultTarget: HistorySearchTarget
    let outcomeTarget: HistorySearchTarget?
    let title: String
    let documents: [SearchDocument]

    init(_ builder: SearchGroupBuilder) {
        id = builder.id
        defaultTarget = builder.defaultTarget
        outcomeTarget = builder.outcomeTarget
        title = builder.title
        documents = builder.documents
    }
}
