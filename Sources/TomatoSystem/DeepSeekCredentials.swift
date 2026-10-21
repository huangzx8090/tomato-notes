import Foundation
import Security

public struct CredentialError: LocalizedError {
    let status: OSStatus
    public var errorDescription: String? { "钥匙串操作失败（\(status)），请检查本机钥匙串权限后重试。" }
}

public struct DeepSeekCredentials {
    public static let service = "com.zixuan.TomatoNotes.deepseek"
    private let service: String
    public init(service: String = Self.service) { self.service = service }

    public func isConfigured() throws -> Bool {
        if Self.environmentKey != nil { return true }
        var query = identity
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

    public func read() throws -> String? {
        if let environment = Self.environmentKey { return environment }
        var query = identity
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
        guard let bytes = result as? Data else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    public func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributes: [CFString: Any] = [kSecValueData: Data(key.utf8)]
        var status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData] = Data(key.utf8)
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
    }

    public func remove() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError(status: status) }
    }

    public static var environmentKey: String? {
        for name in ["deepseek", "DEEPSEEK_API_KEY"] {
            if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
    }

    private var identity: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "api-key"]
    }
}
