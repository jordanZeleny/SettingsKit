import UIKit

enum ChatRole: String, Codable { case assistant, user }

// MARK: - Chat bubble

/// iMessage-style chat bubble with a smooth curved tail. Left/grey for the
/// assistant, right/blue for the user.
final class ChatBubble: UIView {
    private let label = UILabel()
    private let bubble = UIView()
    private let shapeLayer = CAShapeLayer()
    private let pointingLeft: Bool
    private let fillColor: UIColor

    init(role: ChatRole, text: String) {
        pointingLeft = (role == .assistant)
        fillColor = (role == .assistant) ? .secondarySystemBackground : .systemBlue
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = (role == .assistant) ? .label : .white

        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .clear
        shapeLayer.fillColor = fillColor.cgColor
        bubble.layer.addSublayer(shapeLayer)
        bubble.addSubview(label)
        addSubview(bubble)

        let vInset: CGFloat = 9
        let tailInset: CGFloat = 17
        let flatInset: CGFloat = 13

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: vInset),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -vInset),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: pointingLeft ? tailInset : flatInset),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: pointingLeft ? -flatInset : -tailInset),

            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.78),
        ])

        if pointingLeft {
            bubble.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        } else {
            bubble.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = bubble.bounds
        shapeLayer.path = Self.bubblePath(width: bubble.bounds.width,
                                          height: bubble.bounds.height,
                                          pointingLeft: pointingLeft)
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        shapeLayer.fillColor = fillColor.resolvedColor(with: traitCollection).cgColor
    }

    private static func bubblePath(width w: CGFloat, height h: CGFloat, pointingLeft: Bool) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 22, y: h))
        path.addLine(to: CGPoint(x: w - 17, y: h))
        path.addCurve(to: CGPoint(x: w, y: h - 17),
                      controlPoint1: CGPoint(x: w - 7.61, y: h),
                      controlPoint2: CGPoint(x: w, y: h - 7.61))
        path.addLine(to: CGPoint(x: w, y: 17))
        path.addCurve(to: CGPoint(x: w - 17, y: 0),
                      controlPoint1: CGPoint(x: w, y: 7.61),
                      controlPoint2: CGPoint(x: w - 7.61, y: 0))
        path.addLine(to: CGPoint(x: 21, y: 0))
        path.addCurve(to: CGPoint(x: 4, y: 17),
                      controlPoint1: CGPoint(x: 11.61, y: 0),
                      controlPoint2: CGPoint(x: 4, y: 7.61))
        path.addLine(to: CGPoint(x: 4, y: h - 11))
        path.addCurve(to: CGPoint(x: 0, y: h),
                      controlPoint1: CGPoint(x: 4, y: h - 1),
                      controlPoint2: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: -0.05, y: h - 0.01))
        path.addCurve(to: CGPoint(x: 11.04, y: h - 4.04),
                      controlPoint1: CGPoint(x: 4.07, y: h + 0.43),
                      controlPoint2: CGPoint(x: 8.16, y: h - 1.06))
        path.addCurve(to: CGPoint(x: 22, y: h),
                      controlPoint1: CGPoint(x: 16, y: h),
                      controlPoint2: CGPoint(x: 19.83, y: h))
        path.close()
        if !pointingLeft {
            path.apply(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
        }
        return path.cgPath
    }
}

// MARK: - Suggestion cards

final class SuggestionCard: UIButton {
    private let tapHandler: () -> Void

    init(suggestion: AIChatSuggestion, tapHandler: @escaping () -> Void) {
        self.tapHandler = tapHandler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // Real glass button driven entirely by its configuration content, so it
        // gets the full interactive (stretchy) Liquid Glass press like the
        // action/link buttons. Overlaying custom subviews or overriding the
        // background corner radius defeats that, so we use the config instead.
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = .glass()
        } else {
            config = .gray()
        }
        config.cornerStyle = .large
        config.baseForegroundColor = .systemBlue   // icon tint

        config.image = UIImage(systemName: suggestion.icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        config.imagePlacement = .top
        config.imagePadding = 8

        var titleAttr = AttributedString(suggestion.title)
        titleAttr.font = .systemFont(ofSize: 15, weight: .semibold)
        titleAttr.foregroundColor = .label
        config.attributedTitle = titleAttr

        var subAttr = AttributedString(suggestion.subtitle)
        subAttr.font = .systemFont(ofSize: 12)
        subAttr.foregroundColor = .secondaryLabel
        config.attributedSubtitle = subAttr

        config.titleAlignment = .center
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)
        configuration = config

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    @objc private func handleTap() {
        Haptics.soft()
        tapHandler()
    }
}

/// 2×2 grid of suggestion cards, sized to equal widths and heights.
final class SuggestionGridView: UIView {
    init(items: [AIChatSuggestion], tapHandler: @escaping (AIChatSuggestion) -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let cards = items.map { item in
            SuggestionCard(suggestion: item) { tapHandler(item) }
        }
        guard !cards.isEmpty else { return }

        func row(_ views: [UIView]) -> UIStackView {
            let s = UIStackView(arrangedSubviews: views)
            s.axis = .horizontal
            s.spacing = 10
            s.distribution = .fillEqually
            s.alignment = .fill
            return s
        }

        // Lay cards out two per row.
        var rows: [UIStackView] = []
        var i = 0
        while i < cards.count {
            let pair = Array(cards[i..<min(i + 2, cards.count)])
            rows.append(row(pair))
            i += 2
        }

        let col = UIStackView(arrangedSubviews: rows)
        col.axis = .vertical
        col.spacing = 10
        col.distribution = .fillEqually
        col.translatesAutoresizingMaskIntoConstraints = false
        addSubview(col)

        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: topAnchor),
            col.bottomAnchor.constraint(equalTo: bottomAnchor),
            col.leadingAnchor.constraint(equalTo: leadingAnchor),
            col.trailingAnchor.constraint(equalTo: trailingAnchor),
            cards[0].heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

// MARK: - Typing indicator

/// Apple Messages-style three-dot typing indicator in an assistant bubble.
final class TypingIndicatorView: UIView {
    private let bubble = UIView()
    private let dots: [UIView]

    override init(frame: CGRect) {
        dots = (0..<3).map { _ in
            let d = UIView()
            d.backgroundColor = .secondaryLabel
            d.layer.cornerRadius = 4
            d.translatesAutoresizingMaskIntoConstraints = false
            return d
        }
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        bubble.backgroundColor = .secondarySystemBackground
        bubble.layer.cornerRadius = 17
        bubble.layer.cornerCurve = .continuous
        bubble.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubble)

        let stack = UIStackView(arrangedSubviews: dots)
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(stack)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
            bubble.leadingAnchor.constraint(equalTo: leadingAnchor),

            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 13),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -13),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
        ])
        for dot in dots {
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func startAnimating() {
        let now = CACurrentMediaTime()
        for (i, dot) in dots.enumerated() {
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0.3, 1.0, 0.3]
            pulse.keyTimes = [0, 0.5, 1]
            pulse.duration = 1.1
            pulse.repeatCount = .infinity
            pulse.beginTime = now + Double(i) * 0.2
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.layer.add(pulse, forKey: "pulse")
        }
    }
}

// MARK: - Input bar

/// Glass capsule text field with a filled send button, pinned above the keyboard.
final class InputBar: UIView, UITextViewDelegate {

    var onSend: ((String) -> Void)?

    private var isBusy = false

    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 17)
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.textContentType = .oneTimeCode
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.textContainer.lineFragmentPadding = 0
        return tv
    }()

    private let placeholderLabel: UILabel = {
        let l = UILabel()
        l.textColor = .placeholderText
        l.font = .systemFont(ofSize: 17)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let glassBackground: UIVisualEffectView = {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            effect = UIGlassEffect()
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }
        let v = UIVisualEffectView(effect: effect)
        v.layer.cornerRadius = 22
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let textContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let sendButton: UIButton = {
        let b = UIButton()
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private func sendConfiguration(enabled: Bool) -> UIButton.Configuration {
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            if enabled {
                config = .prominentGlass()
                config.baseBackgroundColor = .systemBlue
                config.baseForegroundColor = .white
            } else {
                config = .glass()
                config.baseForegroundColor = .systemGray
            }
        } else {
            config = .filled()
            config.baseBackgroundColor = enabled ? .systemBlue : .systemGray3
            config.baseForegroundColor = .white
        }
        config.cornerStyle = .capsule
        config.image = UIImage(systemName: "arrow.up",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        return config
    }

    private var textViewHeight: CGFloat = 44
    private var textContainerHeight: NSLayoutConstraint!

    init(placeholder: String) {
        super.init(frame: .zero)
        placeholderLabel.text = placeholder
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        textView.delegate = self
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        textContainer.addSubview(glassBackground)
        textContainer.addSubview(textView)
        textContainer.addSubview(placeholderLabel)
        addSubview(textContainer)
        addSubview(sendButton)

        textContainerHeight = textContainer.heightAnchor.constraint(equalToConstant: textViewHeight)

        NSLayoutConstraint.activate([
            glassBackground.topAnchor.constraint(equalTo: textContainer.topAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),
            glassBackground.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),

            textView.topAnchor.constraint(equalTo: textContainer.topAnchor),
            textView.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor, constant: 6),
            textView.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: -6),

            placeholderLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor, constant: 14),
            placeholderLabel.centerYAnchor.constraint(equalTo: textContainer.centerYAnchor),

            textContainerHeight,
            textContainer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            sendButton.leadingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: 6),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        updateSendEnabled()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func focusTextView() { textView.becomeFirstResponder() }

    func setText(_ text: String) {
        textView.text = text
        textViewDidChange(textView)
        textView.becomeFirstResponder()
    }

    func clear() {
        textView.text = ""
        textViewDidChange(textView)
    }

    func setBusy(_ busy: Bool) {
        isBusy = busy
        textView.isEditable = !busy
        updateSendEnabled()
    }

    @objc private func sendTapped() {
        onSend?(textView.text ?? "")
    }

    private func updateSendEnabled() {
        let hasText = !(textView.text ?? "").isEmpty
        placeholderLabel.isHidden = hasText

        let enabled = hasText && !isBusy
        sendButton.isEnabled = enabled
        sendButton.configuration = sendConfiguration(enabled: enabled)
    }

    func textViewDidChange(_ textView: UITextView) {
        updateSendEnabled()
        let maxHeight: CGFloat = 140
        let fit = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let newH = min(max(44, fit.height), maxHeight)
        if abs(textViewHeight - newH) > 0.5 {
            textViewHeight = newH
            textView.isScrollEnabled = newH >= maxHeight
            textContainerHeight.constant = newH
        }
    }
}
