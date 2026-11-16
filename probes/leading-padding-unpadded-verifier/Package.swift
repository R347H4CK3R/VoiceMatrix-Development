// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "UnpaddedFinalASR", platforms: [.macOS("15.0")], dependencies: [
    .package(path: "../../Vendors/FluidAudio")
], targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])])
