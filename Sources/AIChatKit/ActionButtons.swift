import UIKit

/// A tappable action the assistant can offer beneath a message — rendered as a
/// liquid-glass button. `copy` and `openURL` are handled by AIChatKit; `custom`
/// fires the view controller's `onAction` so the host can do app-specific work
/// (show a paywall, run a settings function, etc.).
public struct AIChatAction {
    public enum Kind {
        case copy(String)       // copies the string to the pasteboard
        case openURL(URL)       // opens the URL
        case custom(String)     // forwards the id to `onAction`
    }

    public let title: String
    public let systemImage: String?
    public let kind: Kind

    public init(title: String, systemImage: String? = nil, kind: Kind) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
    }
}

/// A left-aligned column of liquid-glass action buttons shown as an assistant
/// element in the chat.
final class ActionButtonsView: UIView {

    private let onCustom: (String) -> Void

    init(actions: [AIChatAction], onCustom: @escaping (String) -> Void) {
        self.onCustom = onCustom
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])

        for action in actions {
            stack.addArrangedSubview(makeButton(for: action))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func makeButton(for action: AIChatAction) -> UIButton {
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = .prominentGlass()
            config.baseForegroundColor = .systemBlue
        } else {
            config = .tinted()
            config.baseForegroundColor = .systemBlue
            config.baseBackgroundColor = .systemBlue
        }
        config.title = action.title
        if let symbol = action.systemImage {
            config.image = UIImage(systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            config.imagePadding = 6
        }
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)

        let button = ActionButton(action: action)
        button.configuration = config
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return button
    }

    @objc private func tapped(_ sender: ActionButton) {
        let action = sender.action
        switch action.kind {
        case .copy(let value):
            UIPasteboard.general.string = value
            Haptics.success()
            // Brief "Copied!" confirmation on the button itself.
            let original = sender.configuration?.title
            sender.configuration?.title = "Copied!"
            sender.configuration?.image = UIImage(systemName: "checkmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                sender.configuration?.title = original
                if let symbol = action.systemImage {
                    sender.configuration?.image = UIImage(systemName: symbol,
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
                }
            }
        case .openURL(let url):
            Haptics.soft()
            UIApplication.shared.open(url)
        case .custom(let id):
            Haptics.soft()
            onCustom(id)
        }
    }
}

/// UIButton subclass that carries its action payload.
private final class ActionButton: UIButton {
    let action: AIChatAction
    init(action: AIChatAction) {
        self.action = action
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}
