// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BioRA",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BioRA", targets: ["PersonalMac"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "PersonalCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "PersonalMac", dependencies: ["PersonalCore"]),
        .testTarget(name: "PersonalCoreTests", dependencies: ["PersonalCore"]),
        .testTarget(name: "PersonalMacTests", dependencies: ["PersonalMac"]),
    ]
)
