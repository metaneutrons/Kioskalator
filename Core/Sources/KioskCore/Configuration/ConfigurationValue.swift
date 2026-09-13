import Foundation

/// A single configuration value, in the shape JSON and a property list share.
///
/// Configuration reaches Kioskalator from four places with three different
/// representations behind them: a managed preference domain, a JSON document on
/// disk, a JSON document over the network and the user defaults the settings
/// pane writes. Normalising all of them into one value type means the resolver
/// and every accessor are written once instead of three times, and a type
/// mismatch is reported at one place.
public enum ConfigurationValue: Sendable, Equatable {
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([ConfigurationValue])
    case dictionary([String: ConfigurationValue])
}

extension ConfigurationValue {
    public var booleanValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    public var integerValue: Int? {
        switch self {
        case .integer(let value): return value
        case .number(let value) where value == value.rounded(): return Int(value)
        default: return nil
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var arrayValue: [ConfigurationValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var dictionaryValue: [String: ConfigurationValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    /// The strings of a homogeneous string array, or `nil` if any element is not
    /// a string. Deliberately all-or-nothing: silently dropping the one entry
    /// that was mistyped would hand a kiosk a shorter allowlist than its
    /// operator wrote, which is the failure nobody notices.
    public var stringArrayValue: [String]? {
        guard let elements = arrayValue else { return nil }
        var strings: [String] = []
        strings.reserveCapacity(elements.count)
        for element in elements {
            guard let string = element.stringValue else { return nil }
            strings.append(string)
        }
        return strings
    }
}

extension ConfigurationValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ConfigurationValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ConfigurationValue].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unsupported configuration value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        }
    }
}

extension ConfigurationValue {
    /// Converts a property-list or JSON object graph, as `CFPreferences` and
    /// `JSONSerialization` hand it over, into a configuration value.
    ///
    /// `NSNumber` carries no type distinction a Swift `switch` can see, so the
    /// boolean check has to come first: `CFBoolean` bridges to `NSNumber`, and
    /// asking for its integer value succeeds and yields 0 or 1. Without this
    /// order every managed boolean would arrive as an integer and every
    /// boolean-typed key would be rejected as mistyped.
    public init?(propertyList object: Any) {
        switch object {
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .boolean(value.boolValue)
            } else if CFNumberIsFloatType(value) {
                self = .number(value.doubleValue)
            } else {
                self = .integer(value.intValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            var elements: [ConfigurationValue] = []
            elements.reserveCapacity(value.count)
            for element in value {
                guard let converted = ConfigurationValue(propertyList: element) else { return nil }
                elements.append(converted)
            }
            self = .array(elements)
        case let value as [String: Any]:
            var members: [String: ConfigurationValue] = [:]
            members.reserveCapacity(value.count)
            for (memberKey, memberValue) in value {
                guard let converted = ConfigurationValue(propertyList: memberValue) else {
                    return nil
                }
                members[memberKey] = converted
            }
            self = .dictionary(members)
        default:
            return nil
        }
    }
}
