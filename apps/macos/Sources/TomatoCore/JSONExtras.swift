import Foundation

/// 保留本端尚未理解的 JSON 字段，保证 Windows 与 macOS 往返时数据不丢失。
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self), !container.pathContainsNumberOnly { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法读取的 JSON 值")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension SingleValueDecodingContainer {
    /// Foundation 把 Bool 也当作 NSNumber 解码；避免把 true 变成 1 的歧义由容器顺序处理。
    var pathContainsNumberOnly: Bool { false }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { return nil }
    init(_ string: String) { self.stringValue = string; self.intValue = nil }
}

/// 让 Codable 类型在解码时收集未知字段，编码时原样写回。
public protocol ExtraFieldPreserving: Codable {
    var extraFields: [String: JSONValue] { get set }
}

extension ExtraFieldPreserving {
    /// 在类型的 init(from:) 末尾调用；known 传该类型已声明的字段名。
    public static func captureExtraFields(from decoder: Decoder, known: Set<String>) throws -> [String: JSONValue] {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var extras: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            extras[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        return extras
    }

    /// 在类型的 encode(to:) 末尾调用，把未知字段写回同一层级。
    public func encodeExtraFields(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in extraFields.sorted(by: { $0.key < $1.key }) {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}
