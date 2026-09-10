// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZappDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ZappDesk",
            targets: ["ZappDesk"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "ZappDesk",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "ZappDesk",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(name: "ZappDeskTests", dependencies: ["ZappDesk"], path: "Tests/ZappDeskTests")
    ]
)
