import Foundation
import Testing
import TomatoCore

struct FocusWhitelistRecommendationTests {
    private var candidates: [FocusWhitelistCandidate] {
        [.init(id: "a0", kind: .app, name: "编辑器", detail: "编写代码"),
         .init(id: "p0", kind: .page, name: "微积分课程", detail: "课程页面")]
    }

    private func response(_ suggestions: [FocusWhitelistSuggestion]) throws -> Data {
        try JSONEncoder().encode(["suggestions": suggestions])
    }

    private func expectInvalidContext(goal: String = "学习微积分", candidates: [FocusWhitelistCandidate]) {
        do {
            try FocusWhitelistRecommendation.validateContext(goal: goal, candidates: candidates)
            Issue.record("无效上下文必须在本地拒绝")
        } catch FocusWhitelistRecommendationError.invalidContext {
        } catch { Issue.record("应返回白名单推荐专用的上下文错误") }
    }

    private func expectInvalidResponse(_ data: Data) {
        do {
            _ = try FocusWhitelistRecommendation.validateResponse(data, goal: "学习微积分", candidates: candidates)
            Issue.record("不完整或扩展的建议不能成为白名单")
        } catch FocusWhitelistRecommendationError.invalidResponse {
        } catch { Issue.record("应返回白名单推荐专用的响应错误") }
    }

    @Test func candidateCodingContainsOnlyPublicDescriptionsAndTemporaryIDs() throws {
        let data = try JSONEncoder().encode(candidates)
        let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(objects.map { Set($0.keys) } == [Set(["id", "kind", "name", "detail"]), Set(["id", "kind", "name", "detail"])])
        #expect(objects.map { $0["id"] } == ["a0", "p0"])
        #expect(objects.map { $0["kind"] } == ["app", "page"])
        #expect(try JSONDecoder().decode([FocusWhitelistCandidate].self, from: data) == candidates)
    }

    @Test func dispositionsAndSuggestionsRoundTripAndRecommendationKeepsUsage() throws {
        let suggestions = [FocusWhitelistDisposition.recommended, .optional, .excluded].enumerated().map {
            FocusWhitelistSuggestion(id: "a\($0.offset)", disposition: $0.element, reason: "用途依据")
        }
        let data = try JSONEncoder().encode(suggestions)
        #expect(try JSONDecoder().decode([FocusWhitelistSuggestion].self, from: data) == suggestions)
        #expect(suggestions.map(\.disposition.rawValue) == ["recommended", "optional", "excluded"])
        let result = FocusWhitelistRecommendation(suggestions: suggestions, inputTokens: 120, outputTokens: 30)
        #expect(result.suggestions == suggestions)
        #expect(result.inputTokens == 120 && result.outputTokens == 30)
    }

    @Test func acceptsExactBatchAndTextBoundariesWithoutTruncation() throws {
        let candidates = (0..<40).map {
            FocusWhitelistCandidate(id: "a\($0)", kind: .app,
                                    name: String(repeating: "名", count: 240), detail: String(repeating: "详", count: 160))
        }
        let goal = String(repeating: "学", count: 300)
        #expect(try FocusWhitelistRecommendation.validateContext(goal: " \n" + goal + "\t ", candidates: candidates) == goal)
        let suggestions = candidates.map { FocusWhitelistSuggestion(id: $0.id, disposition: .excluded, reason: String(repeating: "理", count: 200)) }
        #expect(try FocusWhitelistRecommendation.validateResponse(response(suggestions), goal: goal, candidates: candidates) == suggestions)
    }

    @Test func rejectsEmptyAndOversizedGoalsAndCandidateBatches() {
        for goal in ["", " \n\t ", String(repeating: "学", count: 301)] {
            expectInvalidContext(goal: goal, candidates: candidates)
        }
        expectInvalidContext(candidates: [])
        expectInvalidContext(candidates: (0..<41).map { .init(id: "a\($0)", kind: .app, name: "编辑器", detail: "") })
    }

    @Test func rejectsBlankDuplicateAndOversizedIDs() {
        for id in ["", " \n ", String(repeating: "a", count: 65), "p0"] {
            var invalid = candidates
            invalid[0].id = id
            expectInvalidContext(candidates: invalid)
        }
    }

    @Test func rejectsOversizedNamesAndDetailsRatherThanCropping() {
        var invalid = candidates
        invalid[0].name = String(repeating: "名", count: 241)
        expectInvalidContext(candidates: invalid)
        #expect(invalid[0].name.count == 241)
        invalid = candidates
        invalid[1].detail = String(repeating: "详", count: 161)
        expectInvalidContext(candidates: invalid)
        #expect(invalid[1].detail.count == 161)
    }

    @Test func byteBudgetRejectsHugeCombiningCharacterText() {
        var invalid = candidates
        invalid[0].name = "a" + String(repeating: "\u{0301}", count: FocusWhitelistRecommendation.maximumBatchInputBytes)
        #expect(invalid[0].name.count == 1)
        expectInvalidContext(candidates: invalid)
    }

    @Test func resolvesOnlyExistingIDsRestoresOrderAndTrimsReasons() throws {
        let suggestions: [FocusWhitelistSuggestion] = [
            .init(id: "p0", disposition: .recommended, reason: " \n可用于本轮课程练习\t "),
            .init(id: "a0", disposition: .optional, reason: "尚不清楚是否需要编程")
        ]
        let validated = try FocusWhitelistRecommendation.validateResponse(response(suggestions), goal: "微积分", candidates: candidates)
        #expect(validated.map(\.id) == candidates.map(\.id))
        #expect(validated[0].disposition == .optional)
        #expect(validated[1].reason == "可用于本轮课程练习")
    }

    @Test func everyCandidateMayLegitimatelyBeExcluded() throws {
        let suggestions = candidates.map { FocusWhitelistSuggestion(id: $0.id, disposition: .excluded, reason: "与当前目标无关") }
        #expect(try FocusWhitelistRecommendation.validateResponse(response(suggestions), goal: "练习写作", candidates: candidates) == suggestions)
    }

    @Test func rejectsUnknownDuplicateMissingAndExtraIDs() throws {
        for ids in [["a0", "unknown"], ["a0", "a0"], ["a0"], ["a0", "p0", "p1"], []] {
            let suggestions = ids.map { FocusWhitelistSuggestion(id: $0, disposition: .recommended, reason: "用途依据") }
            expectInvalidResponse(try response(suggestions))
        }
    }

    @Test func rejectsEmptyWhitespaceAndOversizedReasons() throws {
        for reason in ["", " \n\t ", String(repeating: "理", count: 201)] {
            let suggestions: [FocusWhitelistSuggestion] = [
                .init(id: "a0", disposition: .optional, reason: reason),
                .init(id: "p0", disposition: .excluded, reason: "与当前目标无关")
            ]
            expectInvalidResponse(try response(suggestions))
        }
    }

    @Test func rejectsMalformedJSONUnknownDispositionsAndInventedRuleFields() throws {
        let validEntries = [["id": "a0", "disposition": "optional", "reason": "用途待确认"],
                            ["id": "p0", "disposition": "recommended", "reason": "课程练习"]]
        for text in ["", "not json", "{\"suggestions\":[", "[]", "{}", "{\"suggestions\":null}"] {
            expectInvalidResponse(Data(text.utf8))
        }
        for extraKey in ["url", "rules", "bundleID", "windowID"] {
            expectInvalidResponse(try JSONSerialization.data(withJSONObject: ["suggestions": validEntries, extraKey: "invented"]))
            var entries = validEntries
            entries[0][extraKey] = "https://invented.test/"
            expectInvalidResponse(try JSONSerialization.data(withJSONObject: ["suggestions": entries]))
        }
        var invalid = validEntries
        invalid[0]["disposition"] = "allow_everything"
        expectInvalidResponse(try JSONSerialization.data(withJSONObject: ["suggestions": invalid]))
        invalid = validEntries
        invalid[0].removeValue(forKey: "reason")
        expectInvalidResponse(try JSONSerialization.data(withJSONObject: ["suggestions": invalid]))
    }

    @Test func oversizedResponseAndInvalidContextCannotPassResponseValidation() {
        expectInvalidResponse(Data(repeating: 32, count: 1024 * 1024 + 1))
        do {
            _ = try FocusWhitelistRecommendation.validateResponse(Data("{}".utf8), goal: " ", candidates: candidates)
            Issue.record("响应校验也必须验证原始上下文")
        } catch FocusWhitelistRecommendationError.invalidContext {
        } catch { Issue.record("无效上下文应保持专用错误类型") }
    }

    @Test func localizedErrorsDescribeWhitelistAndNeverReferToSavedReviews() {
        for error in [FocusWhitelistRecommendationError.invalidContext, .invalidResponse] {
            #expect(error.localizedDescription.contains("白名单推荐"))
            #expect(!error.localizedDescription.contains("总结"))
            #expect(!error.localizedDescription.contains("回顾"))
        }
    }
}
