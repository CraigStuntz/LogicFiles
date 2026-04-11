// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LogicFiles",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "LogicFiles", targets: ["LogicFiles"]),
    ],
    dependencies: [
        // Used as a command plugin: `swift package plugin "Lint Source Code"`
        .package(url: "https://github.com/swiftlang/swift-format.git", from: "602.0.0"),
    ],
    targets: [
        .target(
            name: "LogicFiles",
            dependencies: [],
            path: "Sources",
            exclude: [
                "Models/AUPRESET_FORMAT.md",
                "Models/CST_FORMAT.md",
                "Models/PATCH_FORMAT.md",
                "Models/PST_FORMAT.md"
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .executableTarget(
            name: "LogicFilesTool",
            dependencies: ["LogicFiles"],
            path: "Tools/LogicFilesTool",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "LogicFilesTests",
            dependencies: ["LogicFiles"],
            path: "Tests",
            resources: [
                .process("Resources/PP.aupreset"),
                .process("Resources/RS2.pst"),
                .process("Resources/sample.pst"),
                .copy("Resources/examples"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
