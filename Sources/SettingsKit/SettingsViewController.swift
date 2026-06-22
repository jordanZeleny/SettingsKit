import UIKit
import MessageUI
import SafariServices
import SuperwallKit

/// Drop-in settings screen shared across the apps. Configure it with a
/// `SettingsConfig` and push or embed it like any other view controller:
///
/// ```swift
/// let config = SettingsConfig(
///     appID: "6757729371",
///     contactEmail: "you@example.com",
///     privacyURL: URL(string: "https://example.com/privacy")!,
///     crossPromoApps: [ /* ... */ ]
/// )
/// let settings = SettingsViewController(config: config)
/// ```
public final class SettingsViewController: UIViewController,
    UITableViewDelegate, UITableViewDataSource, MFMailComposeViewControllerDelegate {

    // MARK: Row model

    private struct Row {
        let title: String
        let image: UIImage?
        let iconColor: UIColor
        /// Full-bleed icon (cross-promo apps) vs. an inset SF Symbol.
        let isAppIcon: Bool
        /// UserDefaults key when this row is a toggle; nil for tappable rows.
        let toggleKey: String?
        let action: () -> Void
    }

    // MARK: State

    private let config: SettingsConfig
    private let keychain: KeychainHelper
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var sections: [[Row]] = []

    // MARK: Init

    public init(config: SettingsConfig) {
        self.config = config
        self.keychain = KeychainHelper(service: config.keychainService)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        buildSections()
        setupUI()
        setupTableView()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Section building

    private func buildSections() {
        var result: [[Row]] = []

        if !isPremium() {
            result.append([
                Row(title: "Upgrade To Pro",
                    image: UIImage(systemName: "crown.fill"),
                    iconColor: config.upgradeIconColor,
                    isAppIcon: false, toggleKey: nil,
                    action: { [weak self] in self?.openPaywall() })
            ])
        }

        result.append([
            Row(title: "Contact Us",
                image: UIImage(systemName: "envelope.fill"),
                iconColor: .systemGreen, isAppIcon: false, toggleKey: nil,
                action: { [weak self] in self?.contact() })
        ])

        result.append([
            Row(title: "Rate This App",
                image: UIImage(systemName: "star.fill"),
                iconColor: .systemYellow, isAppIcon: false, toggleKey: nil,
                action: { [weak self] in self?.review() }),
            Row(title: "Share This App",
                image: UIImage(systemName: "square.and.arrow.up.fill"),
                iconColor: .systemBlue, isAppIcon: false, toggleKey: nil,
                action: { [weak self] in self?.share() })
        ])

        result.append([
            Row(title: "Privacy Policy",
                image: UIImage(systemName: "lock.fill"),
                iconColor: .systemGray, isAppIcon: false, toggleKey: nil,
                action: { [weak self] in self?.openSafari(self?.config.privacyURL) }),
            Row(title: "Terms & Conditions",
                image: UIImage(systemName: "doc.text.fill"),
                iconColor: .systemGray, isAppIcon: false, toggleKey: nil,
                action: { [weak self] in self?.openSafari(self?.config.termsURL) })
        ])

        if !config.crossPromoApps.isEmpty {
            result.append(config.crossPromoApps.map { app in
                Row(title: app.title, image: app.image, iconColor: .systemGray,
                    isAppIcon: true, toggleKey: nil,
                    action: { UIApplication.shared.open(app.url) })
            })
        }

        if config.showDebugRows {
            result.append([
                Row(title: "Premium",
                    image: UIImage(systemName: "dollarsign.circle.fill"),
                    iconColor: .systemGray, isAppIcon: false, toggleKey: "premium",
                    action: {}),
                Row(title: "Show Ratings",
                    image: UIImage(systemName: "star.bubble"),
                    iconColor: .systemGray, isAppIcon: false, toggleKey: "showRatingRequest",
                    action: {}),
                Row(title: "Clear Data",
                    image: UIImage(systemName: "arrow.counterclockwise"),
                    iconColor: .systemGray, isAppIcon: false, toggleKey: nil,
                    action: { [weak self] in self?.eraseUserDefaults() })
            ])
        }

        sections = result
    }

    // MARK: UI

    private func setupUI() {
        navigationItem.title = config.navigationTitle
        view.backgroundColor = .systemBackground

        #if targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *), config.sidebarToggleHandler != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "sidebar.left"),
                style: .plain, target: self, action: #selector(sidebarToggleTapped))
        }
        #endif
    }

    @objc private func sidebarToggleTapped() {
        config.sidebarToggleHandler?()
    }

    private func setupTableView() {
        tableView.frame = view.bounds
        tableView.delegate = self
        tableView.dataSource = self
        tableView.sectionHeaderHeight = 10
        tableView.sectionFooterHeight = 20
        tableView.sectionHeaderTopPadding = 0
        tableView.contentInsetAdjustmentBehavior = .automatic
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = !isMac()
        view.addSubview(tableView)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        // Trim the bottom inset so the last rows scroll up enough to clear the tab bar.
        tableView.contentInset = UIEdgeInsets(top: -16, left: 0, bottom: 0, right: 0)

        tableView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true

        let leading = tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)
        leading.isActive = true
        leading.priority = UILayoutPriority(750)
        let trailing = tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8)
        trailing.isActive = true
        trailing.priority = UILayoutPriority(750)

        tableView.widthAnchor.constraint(lessThanOrEqualToConstant: 650).isActive = true

        addBottomBlur()
    }

    /// Graduated blur fading up from the tab bar, matching the home screens so
    /// content dissolves as it scrolls off the bottom.
    private func addBottomBlur() {
        let blur = ProgressiveBlurView(edge: .bottom)
        blur.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blur)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 30),
            blur.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)
        ])
    }

    // MARK: UITableViewDataSource

    public func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section][indexPath.row]

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.contentView.backgroundColor = .clear
        cell.backgroundColor = config.cellBackgroundColor ?? .secondarySystemGroupedBackground
        cell.accessoryType = .disclosureIndicator

        let button = UIButton()
        button.setTitle(row.title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.setTitleColor(.label, for: .normal)
        button.contentHorizontalAlignment = .left
        cell.contentView.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 64).isActive = true
        button.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -40).isActive = true
        button.topAnchor.constraint(equalTo: cell.topAnchor).isActive = true
        button.bottomAnchor.constraint(equalTo: cell.bottomAnchor).isActive = true
        button.isUserInteractionEnabled = false
        button.backgroundColor = .clear

        if let key = row.toggleKey {
            cell.selectionStyle = .none
            cell.accessoryType = .none
            let switchControl = UISwitch()
            switchControl.isOn = UserDefaults.standard.bool(forKey: key)
            switchControl.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            switchControl.accessibilityIdentifier = key
            cell.accessoryView = switchControl
        } else {
            cell.selectionStyle = .default
        }

        let addCircle = UIView()
        addCircle.backgroundColor = row.iconColor.withAlphaComponent(0.9)
        addCircle.isUserInteractionEnabled = false
        addCircle.clipsToBounds = true
        cell.contentView.addSubview(addCircle)
        addCircle.translatesAutoresizingMaskIntoConstraints = false
        addCircle.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 20).isActive = true
        addCircle.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
        addCircle.heightAnchor.constraint(equalTo: cell.heightAnchor, multiplier: 0.55).isActive = true
        addCircle.widthAnchor.constraint(equalTo: addCircle.heightAnchor).isActive = true
        addCircle.layoutIfNeeded()
        addCircle.layer.cornerRadius = 6

        let iconImageView = UIImageView()
        iconImageView.isUserInteractionEnabled = false
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        addCircle.addSubview(iconImageView)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        if row.isAppIcon {
            NSLayoutConstraint.activate([
                iconImageView.leadingAnchor.constraint(equalTo: addCircle.leadingAnchor),
                iconImageView.trailingAnchor.constraint(equalTo: addCircle.trailingAnchor),
                iconImageView.topAnchor.constraint(equalTo: addCircle.topAnchor),
                iconImageView.bottomAnchor.constraint(equalTo: addCircle.bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                iconImageView.centerYAnchor.constraint(equalTo: addCircle.centerYAnchor),
                iconImageView.centerXAnchor.constraint(equalTo: addCircle.centerXAnchor),
                iconImageView.widthAnchor.constraint(equalToConstant: 20),
                iconImageView.heightAnchor.constraint(equalToConstant: 20)
            ])
        }

        iconImageView.image = row.image
        return cell
    }

    // MARK: UITableViewDelegate

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        50
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? 32 : 0
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = UIView()
        footerView.backgroundColor = .clear
        return footerView
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        sections[indexPath.section][indexPath.row].action()
    }

    // MARK: Actions

    private func openPaywall() {
        Superwall.shared.register(placement: config.paywallPlacement) {}
    }

    private func review() {
        guard let url = URL(string: "https://apps.apple.com/app/id\(config.appID)?action=write-review") else { return }
        UIApplication.shared.open(url)
    }

    private func share() {
        guard let url = URL(string: "https://apps.apple.com/us/app/id\(config.appID)") else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if !isIphone() {
            activityVC.popoverPresentationController?.permittedArrowDirections = .any
            activityVC.popoverPresentationController?.sourceView = navigationController?.navigationBar
        }
        present(activityVC, animated: true)
    }

    private func openSafari(_ url: URL?) {
        guard let url else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    private func contact() {
        sendEmail(to: config.contactEmail)
    }

    private func eraseUserDefaults() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Clear Data", style: .destructive) { [weak self] _ in
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            self?.keychain.clearSaveCount()
            fatalError("Crashing the app intentionally")
        })
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(actionSheet, animated: true)
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        guard let key = sender.accessibilityIdentifier else { return }
        UserDefaults.standard.set(sender.isOn, forKey: key)
    }

    // MARK: Mail

    private func sendEmail(to recipient: String) {
        let appName = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String) ?? "Unknown"
        guard MFMailComposeViewController.canSendMail() else {
            showEmailUnavailableAlert(with: recipient)
            return
        }

        let osName: String
        if isIpad() {
            osName = "iPadOS"
        } else if isMac() {
            osName = "macOS"
        } else {
            osName = "iOS"
        }
        let isPro = isPremium() ? "•" : "."
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        let body =
        """
        \n\n\n\n\n\n\n\n\n\n\n\n\n\n\n
        \(deviceName())
        \(osName) \(UIDevice.current.systemVersion)
        App Version: \(appVersion)\(isPro)
        """

        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = self
        composer.setToRecipients([recipient])
        composer.setSubject("\(appName) App Support")
        composer.setMessageBody(body, isHTML: false)
        present(composer, animated: true)
    }

    public func mailComposeController(_ controller: MFMailComposeViewController,
                                      didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }

    private func showEmailUnavailableAlert(with email: String) {
        let alert = UIAlertController(title: "Contact Developer", message: "", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Open Email App", style: .default) { _ in
            if let encoded = "mailto:\(email)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: encoded), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Copy Email Address", style: .default) { _ in
            UIPasteboard.general.string = email
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: Environment helpers

    private func isPremium() -> Bool {
        Superwall.shared.subscriptionStatus.isActive || UserDefaults.standard.bool(forKey: "premium")
    }

    private func isMac() -> Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    private func isIpad() -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private func isIphone() -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private func deviceName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
    }
}
