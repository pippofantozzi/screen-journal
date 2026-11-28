// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenJournal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScreenJournal", targets: ["ScreenJournal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "JournalCore"),
        .executableTarget(
            name: "ScreenJournal",
            dependencies: [
                "JournalCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "JournalCoreTests", dependencies: ["JournalCore"]),
    ]
)
