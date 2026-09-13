import Foundation

/// Where a value came from. The order of the cases is the precedence order, and
/// `Comparable` follows it, so `managed < user` reads as "managed wins".
public enum ConfigurationOrigin: Int, Sendable, CaseIterable, Comparable {
    case managed = 0
    case remote = 1
    case file = 2
    case user = 3
    case fallback = 4

    public static func < (lhs: ConfigurationOrigin, rhs: ConfigurationOrigin) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .managed: return "managed preferences"
        case .remote: return "remote configuration"
        case .file: return "configuration file"
        case .user: return "settings pane"
        case .fallback: return "built-in default"
        }
    }
}

/// A problem found while reading one layer. Every one of them names the layer,
/// because "a setting had no effect" is unactionable and "the file layer set
/// idleTimeout to a string" is not.
public enum ConfigurationDefect: Sendable, Equatable {
    case unknownKey(name: String, origin: ConfigurationOrigin)
    case wrongKind(key: ConfigurationKey, origin: ConfigurationOrigin, expected: ConfigurationKind)
    case unknownLockName(name: String, origin: ConfigurationOrigin)
    case malformedLockDeclaration(origin: ConfigurationOrigin)
    case unreadableDocument(origin: ConfigurationOrigin, reason: String)

    public var message: String {
        switch self {
        case .unknownKey(let name, let origin):
            return "\(origin.displayName): unknown key '\(name)'"
        case .wrongKind(let key, let origin, let expected):
            return "\(origin.displayName): '\(key.rawValue)' is not \(expected)"
        case .unknownLockName(let name, let origin):
            return "\(origin.displayName): lock declared for unknown key '\(name)'"
        case .malformedLockDeclaration(let origin):
            return "\(origin.displayName): 'locked' is not an array of key names"
        case .unreadableDocument(let origin, let reason):
            return "\(origin.displayName): could not be read (\(reason))"
        }
    }
}

/// One configuration layer, already parsed and validated.
public struct ConfigurationDocument: Sendable, Equatable {
    public let origin: ConfigurationOrigin
    public let values: [ConfigurationKey: ConfigurationValue]
    public let locks: Set<ConfigurationKey>
    public let defects: [ConfigurationDefect]

    public init(
        origin: ConfigurationOrigin,
        values: [ConfigurationKey: ConfigurationValue] = [:],
        locks: Set<ConfigurationKey> = [],
        defects: [ConfigurationDefect] = []
    ) {
        self.origin = origin
        self.values = values
        self.locks = locks
        self.defects = defects
    }

    /// Parses a raw member list into a document, keeping every defect rather
    /// than throwing on the first one. A profile with two typos should report
    /// both, not send its author round the loop twice.
    public init(origin: ConfigurationOrigin, members: [String: ConfigurationValue]) {
        var values: [ConfigurationKey: ConfigurationValue] = [:]
        var locks: Set<ConfigurationKey> = []
        var defects: [ConfigurationDefect] = []

        for (name, value) in members.sorted(by: { $0.key < $1.key }) {
            if name == ConfigurationKey.lockDeclarationName {
                guard let names = value.stringArrayValue else {
                    defects.append(.malformedLockDeclaration(origin: origin))
                    continue
                }
                for lockName in names {
                    if let key = ConfigurationKey(rawValue: lockName) {
                        locks.insert(key)
                    } else {
                        defects.append(.unknownLockName(name: lockName, origin: origin))
                    }
                }
                continue
            }

            guard let key = ConfigurationKey(rawValue: name) else {
                defects.append(.unknownKey(name: name, origin: origin))
                continue
            }
            guard value.matches(kind: key.kind) else {
                defects.append(.wrongKind(key: key, origin: origin, expected: key.kind))
                continue
            }
            values[key] = value
        }

        self.init(origin: origin, values: values, locks: locks, defects: defects)
    }
}

extension ConfigurationValue {
    func matches(kind: ConfigurationKind) -> Bool {
        switch kind {
        case .boolean: return booleanValue != nil
        case .integer: return integerValue != nil
        case .string: return stringValue != nil
        case .stringArray: return stringArrayValue != nil
        case .dictionary: return dictionaryValue != nil
        case .objectArray:
            guard let elements = arrayValue else { return false }
            return elements.allSatisfy { $0.dictionaryValue != nil }
        }
    }
}
