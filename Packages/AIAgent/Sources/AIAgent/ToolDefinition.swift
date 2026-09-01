import Foundation

/// A minimal JSON value for tool argument documents and JSON-schema examples.
/// `indirect` because arrays and objects contain values recursively.
public indirect enum JSONValue: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
            return
        }

        if let double = try? container.decode(Double.self) {
            self = .number(double)
            return
        }

        if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
            return
        }

        if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "JSONValue found a value of an unknown shape."
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .object(dictionary):
            try container.encode(dictionary)
        case let .array(values):
            try container.encode(values)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    // Convenience readers so consumers can pull scalars out of a tool-argument
    // document without pattern-matching the whole tree (spec §2.2).
    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var integerValue: Int? {
        if case let .integer(value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case let .number(value): return value
        case let .integer(value): return Double(value)
        default: return nil
        }
    }

    public var booleanValue: Bool? {
        if case let .boolean(value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(dictionary) = self { return dictionary[key] }
        return nil
    }
}

/// Builds the JSON schema an adapter serializes into the request `tools` payload
/// (spec §2.2). `safeToRunProperty` marks a tool as safe for the auto-review
/// approval tier (spec §4.6 `autoReview`).
public enum JSONSchemaBuilder {
    public enum LiteralType: String {
        case string
        case integer
        case boolean
    }

    /// root-level schema: `{"type": "object", "properties": …, "required": …}`
    public static func object(properties: [String: JSONValue]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
        ])
    }

    public static func string(description: String? = nil) -> JSONValue {
        literal(.string, description: description, enumValues: nil)
    }

    public static func integer(description: String? = nil) -> JSONValue {
        literal(.integer, description: description, enumValues: nil)
    }

    public static func boolean(description: String? = nil) -> JSONValue {
        literal(.boolean, description: description, enumValues: nil)
    }

    /// A string constrained to one of `values` (used for the `kind` field).
    public static func string(enumValues: [String]) -> JSONValue {
        literal(.string, description: nil, enumValues: enumValues)
    }

    public static func array(items: JSONValue) -> JSONValue {
        .object([
            "type": .string("array"),
            "items": items,
        ])
    }

    public static func safeToRunProperty() -> JSONValue {
        .boolean(true)
    }

    private static func literal(
        _ type: LiteralType,
        description: String?,
        enumValues: [String]?
    ) -> JSONValue {
        var fields: [String: JSONValue] = ["type": .string(type.rawValue)]
        if let description {
            fields["description"] = .string(description)
        }
        if let enumValues {
            fields["enum"] = .array(enumValues.map(JSONValue.string))
        }
        return .object(fields)
    }
}

/// A tool exposed to the model (spec §2.2). `parameters` is a JSON-schema object
/// built with `JSONSchemaBuilder`; `isReadonly` feeds the `safe_to_run` flag.
public struct ToolDefinition: Sendable, Equatable {
    public var name: String
    public var description: String
    /// JSON Schema (root object). `JSONValue.object(properties:)` generally.
    public var parameters: JSONValue
    /// Whether this tool is read-only/idempotent (auto-review tier, spec §4.6).
    public var isReadonly: Bool

    public init(name: String, description: String, parameters: JSONValue, isReadonly: Bool = false) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.isReadonly = isReadonly
    }
}