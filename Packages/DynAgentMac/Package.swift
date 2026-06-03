// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DynAgent",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "DynAgent", targets: ["DynAgentHost"]),
        .library(name: "DynAgentUI", type: .dynamic, targets: ["DynAgentUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "DynAgentHost",
            path: "Sources/Host"
        ),
        .target(
            name: "DynAgentUI",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/UI"
        ),
        .testTarget(
            name: "DynAgentUITests",
            dependencies: ["DynAgentUI"],
            path: "Tests/DynAgentUITests"
        )
    ]
)
