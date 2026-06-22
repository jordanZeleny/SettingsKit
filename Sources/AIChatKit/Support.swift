import UIKit

/// Lightweight haptics used by the chat UI (mirrors the host apps' helpers).
enum Haptics {
    static func soft()    { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

/// A blur overlay whose effect fades out toward one edge, mimicking the
/// progressive ("graduated") blur iOS draws under the nav bar as content scrolls.
final class ProgressiveBlurView: UIView {

    enum Edge { case top, bottom }

    private let edge: Edge
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let gradientMask = CAGradientLayer()

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        backgroundColor = .clear

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        gradientMask.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(1).cgColor
        ]
        gradientMask.locations = [0.0, 0.85]
        gradientMask.startPoint = edge == .bottom ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0.5, y: 1)
        gradientMask.endPoint = edge == .bottom ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 0.5, y: 0)
        blurView.layer.mask = gradientMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientMask.frame = blurView.bounds
        CATransaction.commit()
    }
}
