// swift-tools-version: 6.2
// FarolCore: measurement only, no UI (ADR 0006). Zero third-party dependencies (ADR 0014).
import PackageDescription

let package = Package(
    name: "FarolCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FarolCore", targets: ["FarolCore"])
    ],
    targets: [
        .target(
            name: "FarolCore",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "FarolCoreTests", dependencies: ["FarolCore"]),
    ],
    swiftLanguageModes: [.v6]
)
