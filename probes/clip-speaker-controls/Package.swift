// swift-tools-version: 5.10
import PackageDescription
import Foundation

let diagnosticVendorPath = ProcessInfo.processInfo.environment["VOICEMATRIX_DIAGNOSTIC_FLUIDAUDIO_PATH"] ?? "../../Vendors/FluidAudio"

let package = Package(
    name: "RetainedClipSpeakerControls",
    platforms: [.macOS("15.0")],
    dependencies: [.package(path: diagnosticVendorPath)],
    targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])]
)
