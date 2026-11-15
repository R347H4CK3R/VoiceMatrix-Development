import XCTest
import AVFoundation
@testable import VoiceMatrix

@MainActor final class AudioHistorySaveTests: XCTestCase {
    func testTwoRetainedAttemptsSaveSeparatelyWithoutReplacingLegacyRecording() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        let old=UserDefaults.standard.object(forKey:"savedSources")
        defer { try? FileManager.default.removeItem(at:root); if let old { UserDefaults.standard.set(old,forKey:"savedSources") } else { UserDefaults.standard.removeObject(forKey:"savedSources") } }
        let saved=root.appendingPathComponent("Recordings")
        let audio=AudioStore(recordingRoot:saved)
        func wave(_ url:URL,_ sample:Float) throws {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            let format=try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate:24000,channels:1))
            let buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:24000));buffer.frameLength=24000
            for i in 0..<24000 { buffer.floatChannelData![0][i]=sample }
            let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:buffer)
        }
        let legacy=saved.appendingPathComponent("speech.wav");try wave(legacy,0.05);let legacyBytes=try Data(contentsOf:legacy)
        let a=root.appendingPathComponent("CatalogSpeechChecks/11111111-1111-1111-1111-111111111111/speech.wav")
        let b=root.appendingPathComponent("CatalogSpeechChecks/22222222-2222-2222-2222-222222222222/speech.wav")
        try wave(a,0.1);try wave(b,0.2);audio.refresh()
        XCTAssertFalse(audio.isSaved(a));XCTAssertFalse(audio.isSaved(b))
        audio.save(a);XCTAssertTrue(audio.isSaved(a));XCTAssertFalse(audio.isSaved(b))
        audio.save(b);XCTAssertTrue(audio.isSaved(a));XCTAssertTrue(audio.isSaved(b));XCTAssertEqual(audio.recordings.count,3)
        let aSaved=saved.appendingPathComponent(RecordingSaveIdentity.forSource(a).filename)
        let bSaved=saved.appendingPathComponent(RecordingSaveIdentity.forSource(b).filename)
        XCTAssertEqual(try Data(contentsOf:aSaved),try Data(contentsOf:a));XCTAssertEqual(try Data(contentsOf:bSaved),try Data(contentsOf:b))
        XCTAssertEqual(try Data(contentsOf:legacy),legacyBytes)
        audio.rename(SavedAudio(url:aSaved),to:"renamed retained result")
        XCTAssertTrue(audio.isSaved(a));audio.save(a);XCTAssertEqual(audio.recordings.count,3)
        let reloaded=AudioStore(recordingRoot:saved);XCTAssertTrue(reloaded.isSaved(a));XCTAssertTrue(reloaded.isSaved(b))
        reloaded.delete(SavedAudio(url:bSaved));XCTAssertFalse(reloaded.isSaved(b));XCTAssertTrue(reloaded.isSaved(a))
        XCTAssertEqual(try Data(contentsOf:legacy),legacyBytes)
    }
}
