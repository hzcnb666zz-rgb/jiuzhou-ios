// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JiuzhouProtocol",
    products: [.library(name: "JiuzhouProtocol", targets: ["JiuzhouProtocol"])],
    targets: [
        .target(name: "JiuzhouProtocol", path: "Jiuzhou/Core"),
        .testTarget(name: "JiuzhouProtocolTests", dependencies: ["JiuzhouProtocol"], path: "Tests",
                    resources: [.copy("Fixtures")])
    ]
)
