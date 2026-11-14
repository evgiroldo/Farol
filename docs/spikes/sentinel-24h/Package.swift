// swift-tools-version: 6.2
// Throwaway prototype for the 24-hour budget measurement (ADR 0028). Not Farol code.
import PackageDescription

let package = Package(
    name: "SentinelSpike",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../../FarolCore")],
    targets: [
        .executableTarget(
            name: "SentinelSpike",
            dependencies: [.product(name: "FarolCore", package: "FarolCore")]
        )
    ],
    swiftLanguageModes: [.v5]
)
