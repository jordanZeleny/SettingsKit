import UIKit

/// A single cross-promotion app row shown in the bottom "More Apps" section.
public struct CrossPromoApp {
    public let title: String
    /// Full-bleed app icon image (supplied by the host app's asset catalog).
    public let image: UIImage?
    /// App Store URL opened when the row is tapped.
    public let url: URL

    public init(title: String, image: UIImage?, url: URL) {
        self.title = title
        self.image = image
        self.url = url
    }
}

/// All per-app values the settings screen needs. Fill one of these in per app
/// and hand it to `SettingsViewController(config:)`.
public struct SettingsConfig {

    // MARK: App identity
    /// Numeric App Store ID, used for the "Rate" and "Share" links.
    public var appID: String
    /// Address the "Contact Us" mail composer sends to.
    public var contactEmail: String
    /// Opened in an in-app Safari sheet from "Privacy Policy".
    public var privacyURL: URL
    /// Opened in an in-app Safari sheet from "Terms & Conditions".
    /// Defaults to Apple's standard EULA.
    public var termsURL: URL

    // MARK: Paywall
    /// Superwall placement registered when "Upgrade To Pro" is tapped.
    public var paywallPlacement: String

    // MARK: Appearance
    /// Icon background color for the "Upgrade To Pro" row.
    public var upgradeIconColor: UIColor
    /// Row background. Falls back to `secondarySystemGroupedBackground` when nil.
    public var cellBackgroundColor: UIColor?
    /// Title shown in the navigation bar.
    public var navigationTitle: String

    // MARK: Sections
    /// Cross-promo apps shown in the bottom section. Empty hides the section.
    public var crossPromoApps: [CrossPromoApp]

    // MARK: Behavior
    /// Keychain service string used when clearing the saved-usage count.
    public var keychainService: String
    /// When true, appends the debug-only rows (Premium / Show Ratings / Clear
    /// Data). Defaults to true on DEBUG builds, false otherwise.
    public var showDebugRows: Bool
    /// When set, a sidebar-toggle bar button appears on Mac Catalyst (iOS 18+).
    public var sidebarToggleHandler: (() -> Void)?

    public init(
        appID: String,
        contactEmail: String,
        privacyURL: URL,
        termsURL: URL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
        paywallPlacement: String = "settings_button",
        upgradeIconColor: UIColor = .systemPurple,
        cellBackgroundColor: UIColor? = nil,
        navigationTitle: String = "Settings",
        crossPromoApps: [CrossPromoApp] = [],
        keychainService: String = "com.slowmo.app",
        showDebugRows: Bool? = nil,
        sidebarToggleHandler: (() -> Void)? = nil
    ) {
        self.appID = appID
        self.contactEmail = contactEmail
        self.privacyURL = privacyURL
        self.termsURL = termsURL
        self.paywallPlacement = paywallPlacement
        self.upgradeIconColor = upgradeIconColor
        self.cellBackgroundColor = cellBackgroundColor
        self.navigationTitle = navigationTitle
        self.crossPromoApps = crossPromoApps
        self.keychainService = keychainService
        #if DEBUG
        self.showDebugRows = showDebugRows ?? true
        #else
        self.showDebugRows = showDebugRows ?? false
        #endif
        self.sidebarToggleHandler = sidebarToggleHandler
    }
}
