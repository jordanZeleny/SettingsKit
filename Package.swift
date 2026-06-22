// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SettingsKit",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15)
    ],
    products: [
        .library(name: "SettingsKit", targets: ["SettingsKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/superwall-me/Superwall-iOS", from: "4.12.0")
    ],
    targets: [
        .target(
            name: "SettingsKit",
            dependencies: [
                .product(name: "SuperwallKit", package: "Superwall-iOS")
            ]
        )
    ]
)
