import Foundation

/// 仅含可发送给 AI 的候选描述；真实应用、页面及窗口的映射留在 UI 本地。
public struct FocusWhitelistCandidate: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case app, page }
    public var id: String
    public var kind: Kind
    public var name: String
    public var detail: String

    public init(id: String, kind: Kind, name: String, detail: String) {
        self.id = id; self.kind = kind; self.name = name; self.detail = detail
    }
}

public enum FocusWhitelistDisposition: String, Codable, Sendable {
    case recommended, optional, excluded
}

public struct FocusWhitelistSuggestion: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var disposition: FocusWhitelistDisposition
    public var reason: String

    public init(id: String, disposition: FocusWhitelistDisposition, reason: String) {
        self.id = id; self.disposition = disposition; self.reason = reason
    }
}

public struct FocusWhitelistRecommendation: Sendable {
    public var suggestions: [FocusWhitelistSuggestion]
    public var inputTokens: Int
    public var outputTokens: Int

    public init(suggestions: [FocusWhitelistSuggestion], inputTokens: Int, outputTokens: Int) {
        self.suggestions = suggestions; self.inputTokens = inputTokens; self.outputTokens = outputTokens
    }

    public static let maximumCandidatesPerBatch = 40
    /// 允许最多 10,240 项，超限时整组报错，避免只推荐名单的一部分。
    public static let maximumBatchCount = 256
    public static let maximumInputBytes = 16 * 1024 * 1024
    public static let maximumBatchInputBytes = 128 * 1024

    /// 校验单批上下文并返回去除首尾空白的目标；字节预算同时约束异常 Unicode 输入。
    @discardableResult
    public static func validateContext(goal: String, candidates: [FocusWhitelistCandidate]) throws -> String {
        let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, goal.count <= 300,
              !candidates.isEmpty, candidates.count <= maximumCandidatesPerBatch else {
            throw FocusWhitelistRecommendationError.invalidContext
        }
        var ids = Set<String>()
        var byteCount = goal.utf8.count
        guard byteCount <= maximumBatchInputBytes else { throw FocusWhitelistRecommendationError.invalidContext }
        for candidate in candidates {
            guard !candidate.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  candidate.id.count <= 64, ids.insert(candidate.id).inserted,
                  candidate.name.count <= 240, candidate.detail.count <= 160 else {
                throw FocusWhitelistRecommendationError.invalidContext
            }
            // 逐字段限额后再相加，避免极端大字符串引起计数溢出。
            for field in [candidate.id, candidate.kind.rawValue, candidate.name, candidate.detail] {
                guard field.utf8.count <= maximumBatchInputBytes - byteCount else {
                    throw FocusWhitelistRecommendationError.invalidContext
                }
                byteCount += field.utf8.count
            }
        }
        return goal
    }

    /// 只接受既有候选的一对一建议，拒绝规则、URL 等扩展字段，并按候选顺序返回。
    public static func validateResponse(_ data: Data, goal: String,
                                        candidates: [FocusWhitelistCandidate]) throws -> [FocusWhitelistSuggestion] {
        try validateContext(goal: goal, candidates: candidates)
        guard data.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["suggestions"],
              let entries = object["suggestions"] as? [[String: Any]],
              entries.count == candidates.count,
              entries.allSatisfy({ Set($0.keys) == ["id", "disposition", "reason"] }),
              let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw FocusWhitelistRecommendationError.invalidResponse
        }
        let candidateIDs = Set(candidates.map(\.id))
        var byID: [String: FocusWhitelistSuggestion] = [:]
        for suggestion in response.suggestions {
            let reason = suggestion.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidateIDs.contains(suggestion.id), byID[suggestion.id] == nil,
                  !reason.isEmpty, suggestion.reason.count <= 200 else {
                throw FocusWhitelistRecommendationError.invalidResponse
            }
            byID[suggestion.id] = .init(id: suggestion.id, disposition: suggestion.disposition, reason: reason)
        }
        guard byID.count == candidates.count else { throw FocusWhitelistRecommendationError.invalidResponse }
        return try candidates.map {
            guard let suggestion = byID[$0.id] else { throw FocusWhitelistRecommendationError.invalidResponse }
            return suggestion
        }
    }

    private struct Response: Decodable {
        let suggestions: [FocusWhitelistSuggestion]
    }
}

public enum FocusWhitelistRecommendationError: LocalizedError {
    case invalidContext, invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidContext:
            "白名单推荐资料过多或格式异常，请精简目标后重新读取。"
        case .invalidResponse:
            "未能取得完整有效的白名单推荐，请检查网络或服务配置后重试。"
        }
    }
}
