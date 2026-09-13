import Foundation

/// One key after every layer has had its say.
public struct ResolvedSetting: Sendable, Equatable, Identifiable {
    public var id: ConfigurationKey { key }

    public let key: ConfigurationKey
    public let value: ConfigurationValue?
    /// Where the winning value came from. `.fallback` means the built-in
    /// default; the settings pane says so rather than showing an empty field of
    /// unknown provenance.
    public let origin: ConfigurationOrigin
    /// The layer holding the lock, or `nil` when the key is free. A key whose
    /// lock is held at or above `.user` cannot be written from the settings
    /// pane.
    public let lockedBy: ConfigurationOrigin?

    public var isEditableFromSettings: Bool { lockedBy == nil }
}

/// A write a lower layer attempted and did not get.
///
/// These are kept and shown, not dropped. A setting that appears to save and
/// then does not is the most expensive kind of support call on a machine nobody
/// is sitting at.
public struct ConfigurationRejection: Sendable, Equatable {
    public let key: ConfigurationKey
    public let attemptedBy: ConfigurationOrigin
    public let lockedBy: ConfigurationOrigin

    public var message: String {
        "\(attemptedBy.displayName) may not set '\(key.rawValue)': "
            + "locked by \(lockedBy.displayName)"
    }
}

public struct ResolvedConfiguration: Sendable, Equatable {
    public let settings: [ConfigurationKey: ResolvedSetting]
    public let rejections: [ConfigurationRejection]
    public let defects: [ConfigurationDefect]

    public subscript(key: ConfigurationKey) -> ConfigurationValue? {
        settings[key]?.value
    }

    public func setting(for key: ConfigurationKey) -> ResolvedSetting? {
        settings[key]
    }
}

/// Merges the layers into one answer per key.
///
/// The rules, in the order they apply:
///
/// 1. Layers are consulted by precedence and the first value wins.
/// 2. A lock declared by a layer applies downward. Once a key is locked, every
///    lower layer that also supplies it is refused and the attempt is recorded.
/// 3. A lock declared without a value adopts the next lower value and freezes
///    it there. That lets a profile pin a per-machine setting it does not know
///    the value of.
public enum ConfigurationResolver {
    public static func resolve(_ documents: [ConfigurationDocument]) -> ResolvedConfiguration {
        let ordered = documents.sorted { $0.origin < $1.origin }
        var settings: [ConfigurationKey: ResolvedSetting] = [:]
        var rejections: [ConfigurationRejection] = []

        for key in ConfigurationKey.allCases {
            let lockHolder = ordered.first { $0.locks.contains(key) }?.origin
            let suppliers = ordered.filter { $0.values[key] != nil }

            let winner = suppliers.first
            let value = winner?.values[key] ?? key.defaultValue
            let origin = winner?.origin ?? .fallback

            // A lock declared above the winning layer is adopted by that layer:
            // the value is taken from where it actually came from, and every
            // layer below it is refused.
            let effectiveLock = lockHolder.map { holder in max(holder, origin) }

            settings[key] = ResolvedSetting(
                key: key,
                value: value,
                origin: origin,
                lockedBy: effectiveLock
            )

            guard let effectiveLock else { continue }
            for supplier in suppliers where supplier.origin > effectiveLock {
                rejections.append(
                    ConfigurationRejection(
                        key: key,
                        attemptedBy: supplier.origin,
                        lockedBy: effectiveLock
                    )
                )
            }
        }

        return ResolvedConfiguration(
            settings: settings,
            rejections: rejections,
            defects: ordered.flatMap(\.defects)
        )
    }
}
