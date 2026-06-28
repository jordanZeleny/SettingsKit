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

// MARK: - Chat image bubble

/// A rounded image attachment shown inline in the chat, aligned to the sender's
/// side (right/user, left/assistant). Used to display a photo the user uploaded
/// alongside their message. Sized to the image's aspect ratio, capped in width.
final class ChatImageBubble: UIView {
    init(role: ChatRole, image: UIImage) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 18
        imageView.layer.cornerCurve = .continuous
        addSubview(imageView)

        let pointingLeft = (role == .assistant)
        let aspect = max(image.size.height, 1) / max(image.size.width, 1)

        let preferredWidth = imageView.widthAnchor.constraint(equalToConstant: 220)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.6),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspect),
            preferredWidth,
        ])

        if pointingLeft {
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        } else {
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

// MARK: - Suggestion cards

final class SuggestionCard: UIControl {
    private let tapHandler: () -> Void

    init(suggestion: AIChatSuggestion, menu: UIMenu? = nil, tapHandler: @escaping () -> Void) {
        self.tapHandler = tapHandler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let glass: UIVisualEffectView
        if #available(iOS 26.0, *) {
            glass = UIVisualEffectView(effect: UIGlassEffect())
        } else {
            glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
        glass.isUserInteractionEnabled = false
        glass.layer.cornerRadius = 18
        glass.layer.cornerCurve = .continuous
        glass.clipsToBounds = true
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        let icon = UIImageView(image: UIImage(systemName: suggestion.icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        icon.tintColor = .systemBlue
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = suggestion.title
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .label
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = suggestion.subtitle
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 2
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        for v in [icon, title, subtitle] {
            v.isUserInteractionEnabled = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),

            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])

        if let menu {
            // Tapping the card opens the same attach menu as the input bar's + button.
            let overlay = UIButton(type: .system)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.menu = menu
            overlay.showsMenuAsPrimaryAction = true
            addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: topAnchor),
                overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        } else {
            addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    @objc private func handleTap() {
        Haptics.soft()
        tapHandler()
    }
    // No press-down animation.
}

/// 2×2 grid of suggestion cards, sized to equal widths and heights.
final class SuggestionGridView: UIView {
    init(items: [AIChatSuggestion],
         menuProvider: ((AIChatSuggestion) -> UIMenu?)? = nil,
         tapHandler: @escaping (AIChatSuggestion) -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let cards = items.map { item in
            SuggestionCard(suggestion: item, menu: menuProvider?(item)) { tapHandler(item) }
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

/// A UITextView that turns a pasted image into an attachment instead of pasting
/// it as text/attributed content.
final class AttachTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
        if pb.hasImages, let image = pb.image {
            onPasteImage?(image)
            return
        }
        super.paste(sender)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

/// Glass capsule text field with a filled send button, pinned above the keyboard.
final class InputBar: UIView, UITextViewDelegate {

    var onSend: ((String, [UIImage]) -> Void)?

    /// Pending image attachments shown as small squares above the field.
    private(set) var attachments: [UIImage] = []

    private var isBusy = false

    private let plusButton: UIButton = {
        let b = UIButton()
        b.translatesAutoresizingMaskIntoConstraints = false
        b.showsMenuAsPrimaryAction = true
        return b
    }()

    /// Thumbnails hover at the top-left inside the field, over reserved newlines.
    private let attachmentsStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 6
        s.translatesAutoresizingMaskIntoConstraints = false
        s.isHidden = true
        return s
    }()

    private let thumbSide: CGFloat = 73   // 40% larger
    /// Empty lines reserved at the top of the field so typed text sits below the
    /// hovering image(s).
    private let reserveNewlines = "\n\n\n\n"

    private let textView: AttachTextView = {
        let tv = AttachTextView()
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
        textView.onPasteImage = { [weak self] image in self?.addAttachment(image) }
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        plusButton.configuration = plusConfiguration()

        textContainer.addSubview(glassBackground)
        textContainer.addSubview(textView)
        textContainer.addSubview(placeholderLabel)
        textContainer.addSubview(attachmentsStack)   // overlay, on top of the text
        addSubview(plusButton)
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

            // Image thumbnails hover at the top-left, inside the field.
            attachmentsStack.topAnchor.constraint(equalTo: textContainer.topAnchor, constant: 10),
            attachmentsStack.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor, constant: 14),
            attachmentsStack.trailingAnchor.constraint(lessThanOrEqualTo: textContainer.trailingAnchor, constant: -14),

            // Plus (attach) button on the leading edge
            plusButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            plusButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            plusButton.widthAnchor.constraint(equalToConstant: 44),
            plusButton.heightAnchor.constraint(equalToConstant: 44),

            // Text field between the plus and send buttons
            textContainerHeight,
            textContainer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textContainer.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 6),

            sendButton.leadingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: 6),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        updateSendEnabled()
    }

    private func plusConfiguration() -> UIButton.Configuration {
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = .glass()
            config.baseForegroundColor = .systemBlue
        } else {
            config = .filled()
            config.baseBackgroundColor = .systemGray5
            config.baseForegroundColor = .systemBlue
        }
        config.cornerStyle = .capsule
        config.image = UIImage(systemName: "plus",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        return config
    }

    /// Attaches the camera/photos/files menu shown by the plus button.
    func setAttachmentMenu(_ menu: UIMenu) { plusButton.menu = menu }

    func addAttachment(_ image: UIImage) {
        attachments.append(image)
        rebuildAttachments()
        textView.becomeFirstResponder()
        let end = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: end, length: 0)
    }

    func clearAttachments() {
        attachments.removeAll()
        rebuildAttachments()
    }

    private func rebuildAttachments() {
        attachmentsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, img) in attachments.enumerated() {
            attachmentsStack.addArrangedSubview(makeThumb(image: img, index: i))
        }
        let has = !attachments.isEmpty
        attachmentsStack.isHidden = !has
        updateReserveNewlines(present: has)
        updateSendEnabled()
        textViewDidChange(textView)
    }

    /// Keeps exactly the reserved blank lines at the top of the field while images
    /// are attached, so the hovering thumbnails don't cover typed text.
    private func updateReserveNewlines(present: Bool) {
        let current = textView.text ?? ""
        if present {
            if !current.hasPrefix(reserveNewlines) {
                textView.text = reserveNewlines + current
            }
        } else if current.hasPrefix(reserveNewlines) {
            textView.text = String(current.dropFirst(reserveNewlines.count))
        }
    }

    /// A small iOS-style square thumbnail with a remove badge.
    private func makeThumb(image: UIImage, index: Int) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.layer.cornerCurve = .continuous
        iv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iv)

        let remove = UIButton()
        var rc = UIButton.Configuration.plain()
        rc.image = UIImage(systemName: "xmark.circle.fill",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))
        rc.contentInsets = .zero
        remove.configuration = rc
        remove.tintColor = .secondaryLabel
        remove.translatesAutoresizingMaskIntoConstraints = false
        remove.addAction(UIAction { [weak self] _ in
            guard let self, index < self.attachments.count else { return }
            self.attachments.remove(at: index)
            self.rebuildAttachments()
        }, for: .touchUpInside)
        container.addSubview(remove)

        // Inset the image by half the badge so the badge can straddle the image's
        // top-right corner (half OUTSIDE the image) while still sitting fully inside
        // the container — touches outside the container aren't delivered, so this is
        // what keeps the whole badge tappable.
        let badge: CGFloat = 22
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: thumbSide),
            iv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            iv.topAnchor.constraint(equalTo: container.topAnchor, constant: badge / 2),
            iv.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -badge / 2),
            iv.heightAnchor.constraint(equalTo: iv.widthAnchor),
            // Centered on the image's top-right corner → half over the image, half off.
            remove.centerXAnchor.constraint(equalTo: iv.trailingAnchor),
            remove.centerYAnchor.constraint(equalTo: iv.topAnchor),
            remove.widthAnchor.constraint(equalToConstant: badge),
            remove.heightAnchor.constraint(equalToConstant: badge),
        ])
        return container
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func focusTextView() { textView.becomeFirstResponder() }

    func setText(_ text: String) {
        // Preserve the reserved blank lines so the text sits below any attachments.
        textView.text = attachments.isEmpty ? text : reserveNewlines + text
        textViewDidChange(textView)
        textView.becomeFirstResponder()
        let end = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: end, length: 0)
    }

    func clear() {
        textView.text = ""
        textViewDidChange(textView)
    }

    func setBusy(_ busy: Bool) {
        isBusy = busy
        textView.isEditable = !busy
        plusButton.isEnabled = !busy
        updateSendEnabled()
    }

    @objc private func sendTapped() {
        onSend?(textView.text ?? "", attachments)
    }

    private func updateSendEnabled() {
        let hasText = !(textView.text ?? "").isEmpty
        placeholderLabel.isHidden = hasText

        let enabled = (hasText || !attachments.isEmpty) && !isBusy
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
