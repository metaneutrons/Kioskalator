import KioskCore
import SwiftUI

/// The settings pane behind the passcode.
///
/// Its job is as much to explain as to edit. Every row names where its value
/// came from, and a row a higher layer has locked is disabled and says which
/// layer holds it. A field that silently refuses to save is the most expensive
/// kind of support call on a machine nobody is sitting at.
struct SettingsView: View {
    let store: ConfigurationStore
    let close: () -> Void

    @State private var editing: ConfigurationKey?
    @State private var draft = ""
    @State private var problem = ""

    private var rows: [ResolvedSetting] {
        ConfigurationKey.allCases.compactMap { store.configuration.setting($0) }
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Configuration").font(.headline)
            Text(
                "Managed preferences win over the remote configuration, which wins over the "
                    + "configuration file, which wins over what is set here."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var table: some View {
        Table(rows) {
            TableColumn("Setting") { row in
                Text(row.key.rawValue).font(.system(.body, design: .monospaced))
            }
            TableColumn("Value") { row in
                Text(display(row))
                    .foregroundStyle(row.value == nil ? .secondary : .primary)
                    .lineLimit(1)
            }
            TableColumn("From") { row in
                Text(row.origin.displayName).foregroundStyle(.secondary)
            }
            TableColumn("Locked by") { row in
                if let lock = row.lockedBy {
                    Label(lock.displayName, systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.configuration.defects.isEmpty {
                ForEach(Array(store.configuration.defects.enumerated()), id: \.offset) { entry in
                    Label(entry.element.message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            ForEach(Array(store.configuration.rejections.enumerated()), id: \.offset) { entry in
                Label(entry.element.message, systemImage: "lock.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !problem.isEmpty {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Reload configuration") { store.reload() }
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func display(_ row: ResolvedSetting) -> String {
        guard let value = row.value else { return "not set" }
        if row.key.isSecret { return "set" }
        switch value {
        case .boolean(let flag): return flag ? "true" : "false"
        case .integer(let number): return String(number)
        case .number(let number): return String(number)
        case .string(let text): return text
        case .array(let elements): return "\(elements.count) entries"
        case .dictionary(let members): return "\(members.count) entries"
        }
    }
}
