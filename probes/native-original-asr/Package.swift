// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OriginalFrontendProductionASRDiagnostic",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../Vendors/FluidAudio")],
    targets: [.executableTarget(name: "Probe", dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio")
    ])]
)
