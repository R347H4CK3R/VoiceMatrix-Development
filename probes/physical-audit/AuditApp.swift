import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Throw and halt rather than allowing a failed XCTest check to carry on mutating the audit sandbox.
enum AuditAssertion: Error { case failed(UInt) }
func auditUnwrap<T>(_ value: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                    line: UInt = #line) throws -> T {
    guard let value = try value() else { throw AuditAssertion.failed(line) }
    return value
}
func auditEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T,
                               _ message: @autoclosure () -> String = "", line: UInt = #line) throws {
    guard try left() == right() else { throw AuditAssertion.failed(line) }
}
func auditNotEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T,
                                  _ message: @autoclosure () -> String = "", line: UInt = #line) throws {
    guard try left() != right() else { throw AuditAssertion.failed(line) }
}
func auditTrue(_ value: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
               line: UInt = #line) throws {
    guard try value() else { throw AuditAssertion.failed(line) }
}
func auditFalse(_ value: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                line: UInt = #line) throws {
    guard try !value() else { throw AuditAssertion.failed(line) }
}
func auditNil<T>(_ value: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                 line: UInt = #line) throws {
    guard try value() == nil else { throw AuditAssertion.failed(line) }
}
func auditLessThanOrEqual<T: Comparable>(_ left: @autoclosure () throws -> T,
                                         _ right: @autoclosure () throws -> T,
                                         _ message: @autoclosure () -> String = "", line: UInt = #line) throws {
    guard try left() <= right() else { throw AuditAssertion.failed(line) }
}

private struct InternalAuditReport: Decodable {
    struct Row: Decodable {
        let referenceSHA256, manifestSHA256, clipSHA256, previewSHA256, speechSHA256: String
        let wordErrorRate: Double
    }
    let metadataOnly, priorVoicePreserved, identityVerified, liveURLVerified: Bool
    let phaseOnePID, phaseTwoPID: Int32
    let distinctFixtureTurns: Int
    let originalSHA256, mkvSHA256, derivedSHA256: String
    let generated: [Row]
}

private struct AllowlistedAuditReport: Encodable {
    struct Result: Encodable {
        let referenceSHA256, manifestSHA256, clipSHA256, previewSHA256, speechSHA256: String
        let wordErrorRate: Double
    }
    let sourceRevision: String
    let metadataOnly: Bool
    let priorVoicePreserved: Bool
    let distinctProcessRelaunch: Bool
    let physicalIPhoneAudit: Bool
    let identityVerified: Bool
    let liveLinkVerified: Bool
    let distinctFixtureTurns: Int
    let originalSHA256, mkvSHA256, derivedSHA256: String
    let generated: [Result]
}

private struct AuditExport: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@main struct PhysicalAuditApp: App {
    var body: some Scene {
        WindowGroup { NavigationStack { AuditScreen() } }
    }
}

@MainActor private struct AuditScreen: View {
    private enum Step { case unavailable, ready, reopen, second, complete, stopped }
    private struct PhaseMarker: Decodable { let phaseOnePID: Int32 }
    private let phaseTwoStarted = "phase-two-started"
    private let auditID = "com.voicematrix.physicalaudit"
    private let runtimeSource = "42da8f3ed18ca1c0f1462032db5dc05ce77362a1"
    @State private var step: Step = .unavailable
    @State private var confirmedOffline = false
    @State private var running = false
    @State private var exporting = false
    @State private var export: AuditExport?
    @State private var note = ""

    private var validHost: Bool {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        false
        #else
        !ProcessInfo.processInfo.isiOSAppOnMac && UIDevice.current.userInterfaceIdiom == .phone
            && Bundle.main.bundleIdentifier == auditID && !LaptopConnection.paired
        #endif
    }
    private var root: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("strict-f5-proof", isDirectory: true)
    }

    var body: some View {
        Form {
            Section {
                Text("Uses two fixed licensed recordings. It never reads your regular VoiceMatrix library.")
                Text("Before starting either phase, turn on Airplane Mode and turn off Wi-Fi. Keep this audit open while it runs.")
                if step == .ready || step == .second {
                    Toggle("My iPhone is offline", isOn: $confirmedOffline).disabled(running)
                }
            }
            Section {
                switch step {
                case .unavailable:
                    Text("This audit requires its separate app on a physical iPhone.")
                case .ready:
                    Button("Run offline phase 1") { run(first: true) }.disabled(running || !confirmedOffline)
                case .reopen:
                    Text("Phase 1 passed. Swipe this audit app away, then reopen it to unlock phase 2.")
                case .second:
                    Button("Run offline phase 2") { run(first: false) }.disabled(running || !confirmedOffline)
                case .complete:
                    Text("Both phases passed. You can choose to export a report of checks and hashes only.")
                    Button("Export audit report") { makeExport() }.disabled(running)
                case .stopped:
                    Text("The audit stopped. Its test data was retained; your regular app was not touched.")
                }
                if running { ProgressView("Running locally…") }
                if !note.isEmpty { Text(note) }
            }
        }
        .navigationTitle("VoiceMatrix Audit")
        .task { refresh() }
        .fileExporter(isPresented: $exporting, document: export, contentType: .json,
                      defaultFilename: "VoiceMatrix-physical-audit.json") { _ in export = nil }
    }

    private func refresh() {
        guard validHost, let root else { step = .unavailable; return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { step = .ready; return }
        let marker = root.appendingPathComponent("phase-one.json")
        guard let data = try? Data(contentsOf: marker),
              let state = try? JSONDecoder().decode(PhaseMarker.self, from: data), state.phaseOnePID > 0
        else { step = .stopped; return }
        if fm.fileExists(atPath: root.appendingPathComponent("strict-f5-report.json").path) {
            step = (try? exportData(root)) == nil ? .stopped : .complete
        } else if fm.fileExists(atPath: root.appendingPathComponent(phaseTwoStarted).path) {
            step = .stopped
        } else {
            step = state.phaseOnePID == ProcessInfo.processInfo.processIdentifier ? .reopen : .second
        }
    }

    private func run(first: Bool) {
        guard validHost, !running, confirmedOffline, let root,
              (first ? step == .ready : step == .second) else { return }
        running = true
        confirmedOffline = false
        note = ""
        Task { @MainActor in
            defer { running = false }
            do {
                let checks = PhysicalAuditChecks()
                if first { try await checks.testRealStrictSourceSavesTwoReferences() }
                else {
                    try Data().write(to: root.appendingPathComponent(phaseTwoStarted), options: .withoutOverwriting)
                    try await checks.testGeneratesNewSpeechAfterProcessRelaunch()
                }
                refresh()
            } catch let error as AuditAssertion {
                switch error {
                case .failed(let line): note = "A required assertion failed (check \(line))."
                }
                step = .stopped
            } catch {
                note = "A required local operation failed. No data was shared."
                step = .stopped
            }
        }
    }

    private func exportData(_ root: URL) throws -> Data {
        let data = try Data(contentsOf: root.appendingPathComponent("strict-f5-report.json"))
        let raw = try JSONDecoder().decode(InternalAuditReport.self, from: data)
        try auditTrue(raw.metadataOnly && raw.priorVoicePreserved && !raw.identityVerified && !raw.liveURLVerified)
        try auditTrue(raw.phaseOnePID > 0 && raw.phaseTwoPID > 0 && raw.phaseOnePID != raw.phaseTwoPID)
        try auditEqual(raw.distinctFixtureTurns, 2)
        try auditEqual(raw.generated.count, 2)
        var hashes = [raw.originalSHA256, raw.mkvSHA256, raw.derivedSHA256]
        for row in raw.generated {
            try auditTrue(row.wordErrorRate.isFinite && (0...0.1).contains(row.wordErrorRate))
            hashes += [row.referenceSHA256, row.manifestSHA256, row.clipSHA256, row.previewSHA256, row.speechSHA256]
        }
        try auditEqual(hashes.count, Set(hashes).count)
        try auditTrue(hashes.allSatisfy { $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil })
        let report = AllowlistedAuditReport(sourceRevision: runtimeSource, metadataOnly: true,
            priorVoicePreserved: true, distinctProcessRelaunch: true, physicalIPhoneAudit: true,
            identityVerified: false, liveLinkVerified: false, distinctFixtureTurns: 2,
            originalSHA256: raw.originalSHA256, mkvSHA256: raw.mkvSHA256, derivedSHA256: raw.derivedSHA256,
            generated: raw.generated.map { .init(referenceSHA256: $0.referenceSHA256,
                manifestSHA256: $0.manifestSHA256, clipSHA256: $0.clipSHA256,
                previewSHA256: $0.previewSHA256, speechSHA256: $0.speechSHA256, wordErrorRate: $0.wordErrorRate) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(report)
    }

    private func makeExport() {
        guard validHost, step == .complete, let root else { return }
        do { export = AuditExport(data: try exportData(root)); exporting = true }
        catch { note = "The report did not pass privacy and integrity checks." }
    }
}
