// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LogicFiles",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "LogicFiles", targets: ["LogicFiles"]),
        .executable(name: "logicfiles", targets: ["LogicFilesTool"]),
    ],
    dependencies: [
        // Used as a command plugin: `swift package plugin lint-source-code`
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
                "Models/LOGICX_FORMAT.md",
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
        .executableTarget(
            name: "FuzzPst",
            dependencies: ["LogicFiles"],
            path: "Tools/FuzzPst"
        ),
        .executableTarget(
            name: "FuzzAupreset",
            dependencies: ["LogicFiles"],
            path: "Tools/FuzzAupreset"
        ),
        .executableTarget(
            name: "FuzzCst",
            dependencies: ["LogicFiles"],
            path: "Tools/FuzzCst"
        ),
        .executableTarget(
            name: "FuzzPatchData",
            dependencies: ["LogicFiles"],
            path: "Tools/FuzzPatchData"
        ),
        .executableTarget(
            name: "FuzzLogicxProjectInformation",
            dependencies: ["LogicFiles"],
            path: "Tools/FuzzLogicxProjectInformation"
        ),
        .executableTarget(
            name: "FuzzLogicxMetaData",
            dependencies: ["LogicFiles"],
            path: "Tools/FuzzLogicxMetaData"
        ),
        .executableTarget(
            name: "FuzzLogicxDisplayState",
            dependencies: ["LogicFiles"],
            path: "Tools/FuzzLogicxDisplayState"
        ),
        .executableTarget(
            name: "FuzzKeyedArchive",
            dependencies: ["LogicFiles"],
            path: "Tools/FuzzKeyedArchive"
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
