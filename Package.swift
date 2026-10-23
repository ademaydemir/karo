// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Karo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Karo", targets: ["Karo"]),
    ],
    dependencies: [
        // Automatic updates; scripts/build-app.sh embeds Sparkle.framework in the app bundle.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Platform-independent logic: actions, layout math, zone detection. Fully unit-tested.
        .target(name: "KaroCore"),
        // Thin wrappers around the macOS Accessibility API.
        .target(name: "KaroAccessibility", dependencies: ["KaroCore"]),
        // The menu bar app itself (AppKit + SwiftUI).
        .executableTarget(
            name: "Karo",
            dependencies: ["KaroCore", "KaroAccessibility", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework is embedded in Karo.app/Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "KaroCoreTests", dependencies: ["KaroCore"]),
    ]
)
