// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MacMark", platforms: [.macOS(.v14)], products: [
    .executable(name: "MacMark", targets: ["MacMark"])
], targets: [.executableTarget(name: "MacMark", path: "Sources")])
