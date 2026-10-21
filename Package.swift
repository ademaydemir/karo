// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tessera", targets: ["Tessera"]),
    ],
    targets: [
        // Platform-independent logic: actions, layout math, zone detection. Fully unit-tested.
        .target(name: "TesseraCore"),
        // Thin wrappers around the macOS Accessibility API.
        .target(name: "TesseraAccessibility", dependencies: ["TesseraCore"]),
        // The menu bar app itself (AppKit + SwiftUI).
        .executableTarget(name: "Tessera", dependencies: ["TesseraCore", "TesseraAccessibility"]),
        .testTarget(name: "TesseraCoreTests", dependencies: ["TesseraCore"]),
    ]
)
