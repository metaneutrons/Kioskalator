import AppKit

/// The screen shown instead of a page: no configuration, an unreachable home
/// URL, a refused navigation.
///
/// Deliberately not configurable away. A kiosk showing a white page cannot be
/// told apart from a kiosk whose machine has died, and the person who has to
/// make that call is usually on the telephone.
final class NoticeView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 16)
        detailLabel.textColor = .secondaryLabelColor
        hintLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        hintLabel.textColor = .tertiaryLabelColor

        for label in [titleLabel, detailLabel, hintLabel] {
            label.alignment = .center
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
        }

        let stack = NSStackView(views: [titleLabel, detailLabel, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Kioskalator builds its views in code")
    }

    func show(title: String, detail: String, hint: String = "") {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        hintLabel.stringValue = hint
        hintLabel.isHidden = hint.isEmpty
        isHidden = false
    }
}
