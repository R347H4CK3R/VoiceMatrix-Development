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
    func testTwoSeparationPairsSaveAndRenameWithoutAliasing() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        let previous=UserDefaults.standard.object(forKey:"savedSources")
        defer {
            try? FileManager.default.removeItem(at:root)
            if let previous {UserDefaults.standard.set(previous,forKey:"savedSources")}
            else {UserDefaults.standard.removeObject(forKey:"savedSources")}
        }
        let store=SeparationStore(root:root.appendingPathComponent("VocalSeparation"))
        let a=try store.publish(vocals:[0.1,-0.1],accompaniment:[0.2,-0.2],inputName:"first.wav",inputSHA256:String(repeating:"a",count:64))
        let b=try store.publish(vocals:[0.3,-0.3],accompaniment:[0.4,-0.4],inputName:"second.wav",inputSHA256:String(repeating:"b",count:64))
        let urls=[a.vocals,a.accompaniment,b.vocals,b.accompaniment]
        XCTAssertEqual(Set(urls.map{RecordingSaveIdentity.forSource($0).key}).count,4)
        let saved=root.appendingPathComponent("Recordings"),audio=AudioStore(recordingRoot:root.appendingPathComponent("Recordings"))
        for (index,url) in urls.enumerated() {
            XCTAssertFalse(audio.isSaved(url))
            audio.save(url)
            XCTAssertNil(audio.error)
            XCTAssertTrue(audio.isSaved(url))
            XCTAssertEqual(audio.recordings.count,index+1)
            XCTAssertEqual(try Data(contentsOf:saved.appendingPathComponent(RecordingSaveIdentity.forSource(url).filename)),try Data(contentsOf:url))
        }
        let firstSaved=saved.appendingPathComponent(RecordingSaveIdentity.forSource(a.vocals).filename)
        audio.rename(SavedAudio(url:firstSaved),to:"my separated vocal")
        XCTAssertNil(audio.error)
        XCTAssertTrue(audio.isSaved(a.vocals))
        audio.save(a.vocals);XCTAssertEqual(audio.recordings.count,4)
        let reloaded=AudioStore(recordingRoot:saved)
        for url in urls {XCTAssertTrue(reloaded.isSaved(url))}
        XCTAssertEqual(try Data(contentsOf:saved.appendingPathComponent("my separated vocal.wav")),try Data(contentsOf:a.vocals))
        XCTAssertEqual(try store.results().count,2)
    }

}
