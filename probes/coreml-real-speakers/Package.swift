// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "CoreMLRealSpeakers", platforms: [.macOS(.v15)], dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "ee78635d23d52379117554ba72358b65a0612447")
], targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])])
