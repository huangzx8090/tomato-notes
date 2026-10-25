import Foundation

/// AI 服务商配置。除预设外，任何 OpenAI /chat/completions 兼容网关都可以通过自定义 baseURL 接入。
public struct AIProviderConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var defaultModel: String
    /// 请求体是否携带 DeepSeek 风格的 "thinking": {"type": "disabled"} 字段。
    public var sendsThinkingFlag: Bool

    public init(id: String, name: String, baseURL: String, defaultModel: String, sendsThinkingFlag: Bool) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.sendsThinkingFlag = sendsThinkingFlag
    }

    public var apiURL: URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://") else {
            return URL(string: trimmed + "/chat/completions")
        }
        // 无协议时默认 https，避免明文发送密钥。
        return URL(string: "https://" + trimmed + "/chat/completions")
    }
}

public enum AIProviderCatalog {
    public static let deepseek = AIProviderConfig(
        id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com",
        defaultModel: "deepseek-chat", sendsThinkingFlag: true)

    /// 保留旧模型名，用于读取历史数据中的显示。
    public static let legacyDeepSeekModel = "deepseek-flash"

    public static let presets: [AIProviderConfig] = [
        deepseek,
        .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
              defaultModel: "gpt-4o-mini", sendsThinkingFlag: false),
        .init(id: "zhipu", name: "智谱 AI", baseURL: "https://open.bigmodel.cn/api/paas/v4",
              defaultModel: "glm-4v-flash", sendsThinkingFlag: false),
        .init(id: "moonshot", name: "月之暗面 Kimi", baseURL: "https://api.moonshot.cn/v1",
              defaultModel: "moonshot-v1-8k-vision-preview", sendsThinkingFlag: false),
        .init(id: "dashscope", name: "阿里通义", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
              defaultModel: "qwen-vl-plus", sendsThinkingFlag: false),
        .init(id: "siliconflow", name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1",
              defaultModel: "Qwen/Qwen2.5-VL-32B-Instruct", sendsThinkingFlag: false),
        .init(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
              defaultModel: "google/gemini-2.0-flash-001", sendsThinkingFlag: false),
        .init(id: "custom", name: "自定义（OpenAI 兼容）", baseURL: "",
              defaultModel: "", sendsThinkingFlag: false),
    ]

    public static func preset(id: String) -> AIProviderConfig? {
        presets.first { $0.id == id }
    }
}

public struct AISettings: Codable, Sendable, Equatable {
    /// 当前选中的服务商 id（预设 id 或 "custom"）。
    public var providerID = AIProviderCatalog.deepseek.id
    /// 自定义服务商的 baseURL 与模型；预设服务商也可覆盖模型名。
    public var customBaseURL = ""
    public var modelOverride = ""

    public init() {}

    private enum CodingKeys: String, CodingKey { case providerID, customBaseURL, modelOverride }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try values.decodeIfPresent(String.self, forKey: .providerID) ?? AIProviderCatalog.deepseek.id
        customBaseURL = try values.decodeIfPresent(String.self, forKey: .customBaseURL) ?? ""
        modelOverride = try values.decodeIfPresent(String.self, forKey: .modelOverride) ?? ""
    }

    /// 解析当前生效的完整配置：预设作为基底，自定义字段覆盖。
    public func resolved() -> AIProviderConfig {
        let base = AIProviderCatalog.preset(id: providerID) ?? AIProviderCatalog.deepseek
        if providerID == "custom" {
            return AIProviderConfig(id: "custom", name: base.name,
                                    baseURL: customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                    defaultModel: modelOverride.trimmingCharacters(in: .whitespacesAndNewlines),
                                    sendsThinkingFlag: false)
        }
        let override = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIProviderConfig(id: base.id, name: base.name, baseURL: base.baseURL,
                                defaultModel: override.isEmpty ? base.defaultModel : override,
                                sendsThinkingFlag: base.sendsThinkingFlag)
    }
}
