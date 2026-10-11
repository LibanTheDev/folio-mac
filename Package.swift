// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Folio", path: "Sources/Folio"),
        .testTarget(name: "FolioTests", dependencies: ["Folio"], path: "Tests/FolioTests", resources: [.copy("Fixtures")]),
    ]
)
