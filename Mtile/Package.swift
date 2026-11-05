// swift-tools-version: 5.9

// Mtile: the macOS sibling of Wtile (https://github.com/HollowThorn/Wtile). Mirrors Wtile's
// layout: src/Mtile (app) and tests/Mtile.Tests (tests), with the same Bar/Commands/Config/Core/
// Hotkeys/Launcher/Layouts subfolders. Everything that touches AppKit/Accessibility is wrapped
// in `#if os(macOS)`, so the pure parts (layouts, config, key parsing, commands) also build and
// test on Linux/Windows toolchains.

import PackageDescription

let package = Package(
    name: "Mtile",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Mtile", targets: ["Mtile"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Mtile",
            dependencies: [.product(name: "Yams", package: "Yams")],
            path: "src/Mtile"
        ),
        .testTarget(
            name: "Mtile.Tests",
            dependencies: ["Mtile"],
            path: "tests/Mtile.Tests"
        ),
    ]
)
