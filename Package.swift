// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TangentToMidi",
    platforms: [
        .macOS(.v10_15) // CoreMIDI and OSCKit require a recent macOS version
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/orchetect/OSCKit.git", from: "1.2.2"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "TangentToMidi",
            dependencies: ["OSCKit", "Yams"]),
    ]
)
