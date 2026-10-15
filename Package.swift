// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Keyhatch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeyhatchCore", targets: ["KeyhatchCore"]),
        .executable(name: "Keyhatch", targets: ["Keyhatch"])
    ],
    targets: [
        .target(name: "KeyhatchCore"),
        .executableTarget(name: "Keyhatch", dependencies: ["KeyhatchCore"]),
        .executableTarget(name: "KeyhatchChecks", dependencies: ["KeyhatchCore"],
                          path: "Tests/KeyhatchCoreTests")
    ]
)
