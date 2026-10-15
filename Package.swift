// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Handrail",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HandrailCore", targets: ["HandrailCore"]),
        .executable(name: "Handrail", targets: ["Handrail"])
    ],
    targets: [
        .target(name: "HandrailCore"),
        .executableTarget(name: "Handrail", dependencies: ["HandrailCore"]),
        .executableTarget(name: "HandrailChecks", dependencies: ["HandrailCore"],
                          path: "Tests/HandrailCoreTests")
    ]
)
