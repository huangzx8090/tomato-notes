import Foundation
import Security
import TomatoCore

public struct CredentialError: LocalizedError {
    let status: OSStatus
    public var errorDescription: String? { "钥匙串操作失败（\(status)），请检查本机钥匙串权限后重试。" }
}

/// 按 AI 服务商 id 存取 API Key；每个服务商在钥匙串中有独立条目，可同时保存、随时切换。
public struct AIProviderCredentials {
    public static let service = "com.zixuan.TomatoNotes.ai"
    /// 旧版单服务商时代使用的钥匙串条目，迁移时读取。
    public static let legacyService = "com.zixuan.TomatoNotes.deepseek"
    public static let legacyAccount = "api-key"

    private let service: String
    public init(service: String = Self.service) { self.service = service }

    /// 环境变量优先：deepseek / DEEPSEEK_API_KEY 兼容旧名；AI_API_KEY / OPENAI_API_KEY 等通用名在前缀匹配后生效。
    public static func environmentKey(for providerID: String) -> String? {
        let names = Self.environmentNames(for: providerID)
        for name in names {
            if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func environmentNames(for providerID: String) -> [String] {
        var names = ["AI_API_KEY"]
        let suffix = providerID.uppercased().replacingOccurrences(of: "-", with: "_")
        names.append("\(suffix)_API_KEY")
        if providerID == "deepseek" { names.append(contentsOf: ["deepseek", "DEEPSEEK_API_KEY"]) }
        return names
    }

    public func isConfigured(providerID: String) throws -> Bool {
        if Self.environmentKey(for: providerID) != nil { return true }
        var query = identity(providerID: providerID)
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            // 新条目不存在时回退检查旧版 DeepSeek 条目，老用户无感迁移。
            if providerID == AIProviderCatalog.deepseek.id { return try legacyConfigured() }
            return false
        }
        if status == errSecInteractionNotAllowed { return true }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
        return true
    }

    public func read(providerID: String) throws -> String? {
        if let environment = Self.environmentKey(for: providerID) { return environment }
        var query = identity(providerID: providerID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            if providerID == AIProviderCatalog.deepseek.id { return try legacyRead() }
            return nil
        }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
        guard let bytes = result as? Data else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    public func save(_ value: String, providerID: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributes: [CFString: Any] = [kSecValueData: Data(key.utf8)]
        var status = SecItemUpdate(identity(providerID: providerID) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity(providerID: providerID)
            item[kSecValueData] = Data(key.utf8)
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
    }

    public func remove(providerID: String) throws {
        let status = SecItemDelete(identity(providerID: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError(status: status) }
    }

    private var legacyIdentity: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.legacyService, kSecAttrAccount: Self.legacyAccount]
    }

    private func legacyConfigured() throws -> Bool {
        var query = legacyIdentity
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        if status == errSecInteractionNotAllowed { return true }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
        return true
    }

    private func legacyRead() throws -> String? {
        var query = legacyIdentity
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
        guard let bytes = result as? Data else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    private func identity(providerID: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "api-key-\(providerID)"]
    }
}

/// 兼容旧调用方的薄封装：迁移期内等价于当前选中 DeepSeek 的密钥操作。
public typealias DeepSeekCredentials = AIProviderCredentials

public extension AIProviderCredentials {
    /// 兼容 TomatoDataTool 旧接口：读取 deepseek 环境变量。
    static var environmentKey: String? { environmentKey(for: AIProviderCatalog.deepseek.id) }
}
