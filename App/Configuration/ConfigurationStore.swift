import Foundation
import KioskCore

/// Assembles the four layers and keeps the resolved configuration.
///
/// The store owns one more job than the resolver: turning a plaintext exit
/// passcode an administrator typed into a configuration document into a stored
/// record. Nobody is going to type a PBKDF2 record by hand, so the plaintext
/// route has to exist; leaving the plaintext on disk afterwards would make it
/// pointless.
@MainActor
final class ConfigurationStore {
    private(set) var configuration: KioskConfiguration
    private let fileURL: URL
    private let defaults: UserDefaults

    init(fileURL: URL = ConfigurationSources.fileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.configuration = KioskConfiguration(documents: [])
        reload()
    }

    func reload() {
        migratePlaintextPasscodeIfPresent()

        var documents: [ConfigurationDocument] = [
            ConfigurationSources.managedDocument(),
            ConfigurationSources.userDocument(defaults: defaults),
        ]
        if let file = ConfigurationSources.fileDocument(at: fileURL) {
            documents.append(file)
        }
        configuration = KioskConfiguration(documents: documents)
        report()
    }

    /// Writes a value into the user layer, or refuses it because a higher layer
    /// holds a lock. The refusal is returned rather than logged and swallowed:
    /// the settings pane has to be able to say why the field did not take.
    @discardableResult
    func write(_ value: ConfigurationValue?, for key: ConfigurationKey) -> Result<Void, WriteError>
    {
        if let setting = configuration.setting(key), let lock = setting.lockedBy {
            return .failure(.locked(by: lock))
        }
        if let value {
            defaults.set(value.propertyListObject, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
        reload()
        return .success(())
    }

    enum WriteError: Error {
        case locked(by: ConfigurationOrigin)

        var message: String {
            switch self {
            case .locked(let origin):
                return "This setting is locked by \(origin.displayName) and cannot be changed here."
            }
        }
    }

    /// Replaces a plaintext `exitPasscode` in the configuration file with its
    /// derived record, in place.
    ///
    /// Only the file layer is rewritten. A managed profile is not ours to edit,
    /// and a plaintext passcode pushed by MDM is a finding for the
    /// administrator rather than something to silently repair on one machine
    /// while every other machine in the fleet still carries it.
    private func migratePlaintextPasscodeIfPresent() {
        guard let document = ConfigurationSources.fileDocument(at: fileURL),
            let raw = document.values[.exitPasscode]?.stringValue,
            PasscodeRecord(encoded: raw) == nil
        else { return }

        guard let record = PasscodeRecord(passcode: raw) else {
            Log.configuration.error("the configuration file carries an empty exitPasscode")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard var members = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw CocoaError(.propertyListReadCorrupt) }
            members[ConfigurationKey.exitPasscode.rawValue] = record.encoded
            let rewritten = try JSONSerialization.data(
                withJSONObject: members,
                options: [.prettyPrinted, .sortedKeys]
            )
            try rewritten.write(to: fileURL, options: .atomic)
            Log.configuration.notice("replaced the plaintext exit passcode with its record")
        } catch {
            // Loud on purpose. Carrying on would leave the plaintext passcode on
            // disk while the kiosk behaves as though it were protected.
            Log.configuration.error(
                "could not replace the plaintext exit passcode: \(error.localizedDescription)"
            )
        }
    }

    private func report() {
        for defect in configuration.defects {
            Log.configuration.error("\(defect.message, privacy: .public)")
        }
        for rejection in configuration.rejections {
            Log.configuration.notice("\(rejection.message, privacy: .public)")
        }
        for pattern in configuration.urlPolicy.invalidPatterns {
            Log.configuration.error(
                "allowlist entry could not be parsed: \(pattern, privacy: .public)")
        }
    }
}

extension ConfigurationValue {
    /// The property-list object `UserDefaults` stores.
    var propertyListObject: Any {
        switch self {
        case .boolean(let value): return value
        case .integer(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.propertyListObject)
        case .dictionary(let value): return value.mapValues(\.propertyListObject)
        }
    }
}
