import UIKit

/// A blur overlay whose effect fades out toward one edge, mimicking the
/// progressive ("graduated") blur iOS draws under the nav bar as content
/// scrolls. A gradient mask drives the blur's alpha so it's strongest at the
/// anchored edge and clear at the opposite edge — used here to soften where the
/// table view meets the tab bar at the bottom.
final class ProgressiveBlurView: UIView {

    enum Edge {
        case top, bottom
    }

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

        // Opaque (full blur) at the anchored edge, fading to clear at the other.
        gradientMask.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(1).cgColor
        ]
        // Ease the fall-off so the transition reads smoothly rather than linearly.
        gradientMask.locations = [0.0, 0.85]
        gradientMask.startPoint = edge == .bottom ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0.5, y: 1)
        gradientMask.endPoint = edge == .bottom ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 0.5, y: 0)
        blurView.layer.mask = gradientMask
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientMask.frame = blurView.bounds
        CATransaction.commit()
    }
}
