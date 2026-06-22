# SettingsKit

A drop-in UIKit settings screen shared across my apps — the "Settings" tab with
Upgrade, Contact, Rate, Share, Privacy/Terms, a cross-promo "more apps" section,
and debug-only toggles. Everything app-specific is injected through a
`SettingsConfig`, so the same screen works in every app without editing source.

## Requirements

- iOS 15+ / Mac Catalyst 15+
- [SuperwallKit](https://github.com/superwall-me/Superwall-iOS) 4.12.0+ (pulled in
  automatically as a dependency; used for the paywall and subscription status)

## Installation

In Xcode: **File ▸ Add Package Dependencies…** and enter:

```
https://github.com/jordanZeleny/SettingsKit
```

Or in a `Package.swift`:

```swift
.package(url: "https://github.com/jordanZeleny/SettingsKit", from: "1.0.0")
```

## Usage

```swift
import SettingsKit

let config = SettingsConfig(
    appID: "6757729371",
    contactEmail: "jordanzeleny@gmail.com",
    privacyURL: URL(string: "https://sites.google.com/view/labelprinterprivacypolicy")!,
    upgradeIconColor: UIColor(named: "purchaseSettings")!,
    cellBackgroundColor: UIColor(named: "cellColor"),
    crossPromoApps: [
        CrossPromoApp(title: "Envelope Printer - Labels",
                      image: UIImage(named: "envelope"),
                      url: URL(string: "https://apps.apple.com/app/apple-store/id6446146267")!),
        CrossPromoApp(title: "Photo Printer - Print to Size",
                      image: UIImage(named: "photoprinter"),
                      url: URL(string: "https://apps.apple.com/us/app/id6508168840")!),
        // ...
    ],
    sidebarToggleHandler: { [weak self] in self?.toggleSidebar() } // optional, Catalyst
)

let settings = SettingsViewController(config: config)
// push it, or use it as a tab:
navigationController?.pushViewController(settings, animated: true)
```

### What the config controls

| Field | Purpose | Default |
|-------|---------|---------|
| `appID` | App Store ID for Rate/Share links | — |
| `contactEmail` | "Contact Us" mail recipient | — |
| `privacyURL` | Opened in a Safari sheet | — |
| `termsURL` | Opened in a Safari sheet | Apple standard EULA |
| `paywallPlacement` | Superwall placement for "Upgrade To Pro" | `"settings_button"` |
| `upgradeIconColor` | Icon tile color of the upgrade row | `.systemPurple` |
| `cellBackgroundColor` | Row background | `.secondarySystemGroupedBackground` |
| `navigationTitle` | Nav bar title | `"Settings"` |
| `crossPromoApps` | Bottom "more apps" section (host supplies icons) | empty (section hidden) |
| `keychainService` | Service string cleared by "Clear Data" | `"com.slowmo.app"` |
| `showDebugRows` | Premium / Show Ratings / Clear Data rows | true on DEBUG, else false |
| `sidebarToggleHandler` | Shows a Catalyst sidebar toggle when set | nil |

### Behavior notes

- The **Upgrade To Pro** row is hidden automatically when the user is premium
  (active Superwall subscription or the `premium` UserDefaults flag).
- Debug rows: **Premium** and **Show Ratings** toggle the `premium` /
  `showRatingRequest` UserDefaults keys; **Clear Data** wipes the app's
  UserDefaults domain and keychain save count, then intentionally crashes so the
  app relaunches clean.
