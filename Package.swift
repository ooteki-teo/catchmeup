// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CatchMeUp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CatchMeUp", targets: ["CatchMeUpApp"])
    ],
    targets: [
        .target(name: "CatchMeUpCore"),
        .executableTarget(name: "CatchMeUpApp", dependencies: ["CatchMeUpCore"]),
        .testTarget(name: "CatchMeUpCoreTests", dependencies: ["CatchMeUpCore"])
    ],
    swiftLanguageModes: [.v5]
)
