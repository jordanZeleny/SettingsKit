// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SettingsKit",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16)
    ],
    products: [
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
        .library(name: "AIChatKit", targets: ["AIChatKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/superwall-me/Superwall-iOS", from: "4.12.0"),
        .package(url: "https://github.com/lzell/AIProxySwift", from: "0.150.0")
    ],
    targets: [
        .target(
            name: "SettingsKit",
            dependencies: [
                .product(name: "SuperwallKit", package: "Superwall-iOS")
            ]
        ),
        .target(
            name: "AIChatKit",
            dependencies: [
                .product(name: "AIProxy", package: "AIProxySwift")
            ]
        )
    ]
)
