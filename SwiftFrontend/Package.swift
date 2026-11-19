// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Parakeet231Prototype",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "Parakeet231", targets: ["Parakeet231"]),
        .executable(name: "parakeet231-frontend", targets: ["Parakeet231CLI"])
    ],
    targets: [
        .target(name: "Parakeet231"),
        .executableTarget(name: "Parakeet231CLI", dependencies: ["Parakeet231"]),
        .testTarget(name: "Parakeet231Tests", dependencies: ["Parakeet231"])
    ]
)
