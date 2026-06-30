# SettingsKit

A shared UIKit toolkit for my apps, shipped as one package with **two products**
you link independently:

- **`SettingsKit`** — a drop-in settings screen (Upgrade, Contact, Rate, Share,
  Privacy/Terms, a cross-promo "more apps" section, a Reset App option, and
  debug-only toggles). Depends on SuperwallKit.
- **`AIChatKit`** — a configurable chat-style AI assistant (iMessage-style
  bubbles, suggestion grid, typing indicator, history) with dynamic copy and a
  text-chat or image-generation engine. Depends on AIProxy.

Each product pulls only its own dependencies, so an app that links just
`SettingsKit` never downloads AIProxy, and vice versa. See
[`Sources/AIChatKit`](Sources/AIChatKit) for the AIChatKit API.

## Requirements

- iOS 16+ / Mac Catalyst 16+
- `SettingsKit` → [SuperwallKit](https://github.com/superwall/Superwall-iOS) 4.12.0+
- `AIChatKit` → [AIProxySwift](https://github.com/lzell/AIProxySwift) 0.150.0+

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
    appID: "0000000000",
    contactEmail: "support@example.com",
    privacyURL: URL(string: "https://example.com/privacy")!,
    crossPromoApps: [
        CrossPromoApp(title: "My Other App",
                      image: UIImage(named: "otherAppIcon"),
                      url: URL(string: "https://apps.apple.com/app/id0000000000")!),
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
| `upgradeIconColor` | Icon tile color of the upgrade row | baked-in magenta (no asset needed) |
| `cellBackgroundColor` | Row background | `.secondarySystemGroupedBackground` |
| `navigationTitle` | Nav bar title | `"Settings"` |
| `crossPromoApps` | Bottom "more apps" section (host supplies icons) | empty (section hidden) |
| `showDebugRows` | Premium / Show Ratings toggles (debug only) | true on DEBUG, else false |
| `sidebarToggleHandler` | Shows a Catalyst sidebar toggle when set | nil |

### Behavior notes

- The **Upgrade To Pro** row is hidden automatically when the user is premium
  (active Superwall subscription or the `premium` UserDefaults flag).
- **Reset app & erase all content** (its own section, shown in production too)
  confirms with an explanatory alert, then wipes the app's UserDefaults domain
  and shows a non-dismissable "Quit App to Continue" alert so the user fully
  relaunches into a clean state. Premium users get a second notice first,
  reminding them to tap Restore afterward to renew their purchase.
- Debug-only rows (`showDebugRows`): **Premium** and **Show Ratings** toggle the
  `premium` / `showRatingRequest` UserDefaults keys.
