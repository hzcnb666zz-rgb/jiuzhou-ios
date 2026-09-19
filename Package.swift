// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JiuzhouProtocol",
    platforms: [.macOS(.v12)],
    products: [.library(name: "JiuzhouProtocol", targets: ["JiuzhouProtocol"])],
    targets: [
        .target(name: "JiuzhouProtocol", path: "Jiuzhou",
                exclude: ["AndroidArt", "Assets.xcassets", "AndroidEntryView.swift", "AndroidWorldView.swift", "GameView.swift", "MudRichText.swift", "JiuzhouApp.swift"],
                sources: ["Core", "GameModel.swift", "Transport.swift"]),
        .testTarget(name: "JiuzhouProtocolTests", dependencies: ["JiuzhouProtocol"], path: "Tests",
                    resources: [.copy("Fixtures")])
    ]
)
