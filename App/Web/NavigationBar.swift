import AppKit
import KioskCore

@MainActor
protocol NavigationBarDelegate: AnyObject {
    func navigationBarDidTap(_ button: NavigationBarButton)
}

/// The optional slim bar above the content. Off by default: the content is the
/// product, and a kiosk that offers a back button to a page with nothing behind
/// it invites the visitor to look for somewhere else to go.
@MainActor
final class NavigationBar: NSView {
    static let height: CGFloat = 38

    private weak var delegate: (any NavigationBarDelegate)?
    private var items: [NavigationBarButton: NSButton] = [:]

    init(buttons: [NavigationBarButton], delegate: any NavigationBarDelegate) {
        self.delegate = delegate
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        for button in buttons {
            let control = NSButton(
                title: button.label,
                target: self,
                action: #selector(handle(_:))
            )
            control.bezelStyle = .rounded
            control.tag = button.tag
            stack.addArrangedSubview(control)
            items[button] = control
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Kioskalator builds its views in code")
    }

    func update(canGoBack: Bool, canGoForward: Bool) {
        items[.back]?.isEnabled = canGoBack
        items[.forward]?.isEnabled = canGoForward
    }

    @objc private func handle(_ sender: NSButton) {
        guard let button = NavigationBarButton(tag: sender.tag) else { return }
        delegate?.navigationBarDidTap(button)
    }
}

extension NavigationBarButton {
    var label: String {
        switch self {
        case .back: return "Back"
        case .forward: return "Forward"
        case .reload: return "Reload"
        case .home: return "Home"
        }
    }

    /// `NSButton.tag` is the only identity an AppKit action carries back, so the
    /// mapping is written out in both directions rather than relying on the
    /// declaration order of the enumeration, which a later edit would change.
    var tag: Int {
        switch self {
        case .back: return 1
        case .forward: return 2
        case .reload: return 3
        case .home: return 4
        }
    }

    init?(tag: Int) {
        guard let match = NavigationBarButton.allCases.first(where: { $0.tag == tag }) else {
            return nil
        }
        self = match
    }
}
