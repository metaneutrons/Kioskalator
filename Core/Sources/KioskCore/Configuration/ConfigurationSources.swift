import Foundation

/// Reads the four layers off the system.
///
/// Each reader hands back a `ConfigurationDocument` for its own origin, never a
/// merged result. Merging is the resolver's job, and keeping it there is what
/// makes the precedence and the locking testable without a machine that has an
/// MDM profile installed.
public enum ConfigurationSources {
    public static let preferenceDomain = "com.metaneutrons.kioskalator"
    public static let fileURL = URL(
        filePath: "/Library/Application Support/Kioskalator/configuration.json"
    )

    /// Managed preferences, that is the keys a configuration profile forces.
    ///
    /// `CFPreferencesAppValueIsForced` is the whole point: it separates a value
    /// an administrator pushed from one this user happens to have in their own
    /// defaults. Without that test the managed layer would pick up the user
    /// layer's values and rank them highest, which inverts the entire model.
    public static func managedDocument(domain: String = preferenceDomain) -> ConfigurationDocument {
        var members: [String: ConfigurationValue] = [:]
        var names = ConfigurationKey.allCases.map(\.rawValue)
        names.append(ConfigurationKey.lockDeclarationName)

        for name in names {
            let key = name as CFString
            let appID = domain as CFString
            guard CFPreferencesAppValueIsForced(key, appID) else { continue }
            guard let raw = CFPreferencesCopyAppValue(key, appID) else { continue }
            guard let value = ConfigurationValue(propertyList: raw) else { continue }
            members[name] = value
        }
        return ConfigurationDocument(origin: .managed, members: members)
    }

    /// The administrator's configuration file.
    ///
    /// A missing file is not an error: most installations have only some of the
    /// four layers. A file that exists and does not parse **is** an error, and
    /// it is reported rather than treated as absent, because a kiosk running on
    /// defaults because of a stray comma looks identical to one nobody
    /// configured.
    public static func fileDocument(at url: URL = fileURL) -> ConfigurationDocument? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        do {
            return document(origin: .file, json: try Data(contentsOf: url))
        } catch {
            return ConfigurationDocument(
                origin: .file,
                defects: [.unreadableDocument(origin: .file, reason: error.localizedDescription)]
            )
        }
    }

    public static func document(origin: ConfigurationOrigin, json: Data) -> ConfigurationDocument {
        do {
            let members = try JSONDecoder().decode([String: ConfigurationValue].self, from: json)
            return ConfigurationDocument(origin: origin, members: members)
        } catch {
            return ConfigurationDocument(
                origin: origin,
                defects: [.unreadableDocument(origin: origin, reason: error.localizedDescription)]
            )
        }
    }

    /// What the settings pane wrote, from the user defaults of this application.
    public static func userDocument(defaults: UserDefaults = .standard) -> ConfigurationDocument {
        var members: [String: ConfigurationValue] = [:]
        var names = ConfigurationKey.allCases.map(\.rawValue)
        names.append(ConfigurationKey.lockDeclarationName)

        for name in names {
            guard let raw = defaults.object(forKey: name) else { continue }
            guard let value = ConfigurationValue(propertyList: raw) else { continue }
            members[name] = value
        }
        return ConfigurationDocument(origin: .user, members: members)
    }
}
