import XCTest
@testable import VoiceMatrix
final class LocalStudioEvidenceTests: XCTestCase {
    @MainActor func testSpeakerHandoffSelectsExactRetainedVoiceAndPreservesFailures() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let jobs=root.appendingPathComponent("jobs"), id=UUID(), now=Date()
        let folder=jobs.appendingPathComponent(id.uuidString.lowercased())
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var job=LocalVideoStudio.Job(id:id,created:now,updated:now,stage:"Complete",message:"Synthetic handoff integrity only")
        job.speakerVoiceIDs=[:];job.speakerAssets=[:]
        var profiles:[CharacterReference]=[]
        var originals:[String:Data]=[:]
        for (speaker,byte) in [("one",UInt8(1)),("two",UInt8(2))] {
            let bytes=Data(repeating:byte,count:44), hash=LocalVisualEvidence.digest(bytes), voice="voice-"+speaker
            job.speakerVoiceIDs?[speaker]=voice
            job.speakerAssets?[speaker] = .init(voiceID:voice,referenceFile:"reference-"+speaker+".wav",referenceSHA256:hash,previewFile:"preview-"+speaker+".wav",previewSHA256:hash)
            profiles.append(CharacterReference(id:voice,name:speaker,source:"synthetic",permission:"test fixture",referenceText:"Synthetic reference",schemaVersion:1,kind:"reference",engine:"f5",referenceFile:"reference.wav",referenceSHA256:hash,trainedModel:false,categories:[],referenceBytes:44,seconds:3))
            for name in ["reference-"+speaker+".wav","preview-"+speaker+".wav"] { originals[name]=bytes;try bytes.write(to:folder.appendingPathComponent(name)) }
        }
        let snapshot=try JSONEncoder().encode(job);try snapshot.write(to:folder.appendingPathComponent("job.json"))
        let local=LocalVideoStudio(root:jobs,asrBundle:nil,f5Bundle:nil,speakerBundle:nil)
        let library=CharacterLibrary(supportRoot:root.appendingPathComponent("library"),f5Bundle:nil)
        let audio=AudioStore(recordingRoot:root.appendingPathComponent("recordings"))
        library.profiles=profiles;library.selectedID="unrelated-existing-selection"
        func rejected(_ jobID:UUID?=nil,_ speaker:String="one") {
            let before=library.selectedID
            XCTAssertFalse(local.selectSpeaker(jobID:jobID ?? id,speaker:speaker,library:library,audio:audio))
            XCTAssertEqual(library.selectedID,before)
        }
        rejected(UUID());rejected(id,"missing")
        local.setActive(false);rejected();local.setActive(true)
        library.busy=true;rejected();library.busy=false
        let processing=try XCTUnwrap(audio.claimProcessing());rejected();audio.releaseProcessing(processing)
        let microphone=try XCTUnwrap(audio.claimMicrophone());rejected();audio.releaseMicrophone(microphone)
        library.profiles=[];rejected()
        library.profiles=[profiles[0],profiles[0]];rejected()
        library.profiles=[CharacterReference(id:profiles[0].id,name:"changed",source:"synthetic",permission:"test fixture",referenceText:"Synthetic reference",schemaVersion:1,kind:"reference",engine:"f5",referenceFile:"reference.wav",referenceSHA256:profiles[1].referenceSHA256,trainedModel:false,categories:[],referenceBytes:44,seconds:3)];rejected()
        library.profiles=profiles
        XCTAssertTrue(local.selectSpeaker(jobID:id,speaker:"one",library:library,audio:audio));XCTAssertEqual(library.selectedID,"voice-one")
        XCTAssertTrue(local.selectSpeaker(jobID:id,speaker:"two",library:library,audio:audio));XCTAssertEqual(library.selectedID,"voice-two")
        let changed=Data(repeating:9,count:44);try changed.write(to:folder.appendingPathComponent("preview-one.wav"));rejected()
        XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent("preview-one.wav")),changed)
        for (name,bytes) in originals where name != "preview-one.wav" { XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent(name)),bytes) }
        XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent("job.json")),snapshot)
        XCTAssertFalse(local.busy);XCTAssertFalse(library.busy);XCTAssertFalse(audio.processingInUse)
        XCTAssertEqual(library.profiles,profiles)
    }
    @MainActor func testFreshAcquisitionRequiresCurrentConsentAndPreservesPriorFiles() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let jobs=root.appendingPathComponent("jobs"), now=Date(), id=UUID()
        let oldFolder=jobs.appendingPathComponent(id.uuidString.lowercased())
        try FileManager.default.createDirectory(at:oldFolder,withIntermediateDirectories:true)
        let retained=Data("retained earlier acquisition attempt".utf8)
        let oldReceipt=oldFolder.appendingPathComponent("acquisition.json")
        try retained.write(to:oldReceipt)
        var job=LocalVideoStudio.Job(id:id,created:now,updated:now,stage:"Failed",message:"Synthetic acquisition failure")
        job.originalAcquisitionURL=URL(string:"https://youtu.be/abcdefghijk")
        job.acquisitionURL=URL(string:"https://www.youtube.com/watch?v=abcdefghijk")
        let snapshot=try JSONEncoder().encode(job)
        try snapshot.write(to:oldFolder.appendingPathComponent("job.json"))
        let studio=LocalVideoStudio(root:jobs,asrBundle:nil,f5Bundle:nil,speakerBundle:nil)
        let library=CharacterLibrary(supportRoot:root.appendingPathComponent("library"),f5Bundle:nil)
        let audio=AudioStore(recordingRoot:root.appendingPathComponent("recordings")),speech=SpeechStudio()
        XCTAssertEqual(studio.freshAcquisitionURL,job.acquisitionURL)
        studio.retryAcquisition(jobID:UUID(),authorized:true,library:library,audio:audio,speech:speech)
        XCTAssertEqual(studio.current?.id,id)
        studio.retryAcquisition(jobID:id,authorized:false,library:library,audio:audio,speech:speech)
        XCTAssertEqual(studio.current?.id,id)
        studio.setActive(false)
        studio.retryAcquisition(jobID:id,authorized:true,library:library,audio:audio,speech:speech)
        XCTAssertEqual(studio.current?.id,id)
        studio.setActive(true)
        studio.retryAcquisition(jobID:id,authorized:true,library:library,audio:audio,speech:speech)
        let newID=try XCTUnwrap(studio.current?.id)
        XCTAssertNotEqual(newID,id)
        XCTAssertEqual(studio.current?.acquisitionURL,job.acquisitionURL)
        XCTAssertNil(studio.current?.sourceFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath:jobs.appendingPathComponent(newID.uuidString.lowercased()).appendingPathComponent("acquisition.json").path))
        studio.retryAcquisition(jobID:newID,authorized:true,library:library,audio:audio,speech:speech)
        XCTAssertEqual(studio.current?.id,newID) // Already busy; no second attempt.
        for _ in 0..<100 where studio.busy { try await Task.sleep(nanoseconds:10_000_000) }
        XCTAssertFalse(studio.busy) // Missing local engine stops before any network acquisition.
        XCTAssertEqual(try Data(contentsOf:oldReceipt),retained)
        XCTAssertEqual(try Data(contentsOf:oldFolder.appendingPathComponent("job.json")),snapshot)
        XCTAssertTrue(studio.history.contains { $0.id == id })
    }
    @MainActor func testIndividualSpeakerAssetsSurviveReloadAndRejectChangedBytes() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let now=Date(), id=UUID(), first=Data(repeating:1,count:44), second=Data(repeating:2,count:44)
        let folder=root.appendingPathComponent(id.uuidString.lowercased())
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var job=LocalVideoStudio.Job(id:id,created:now,updated:now,stage:"Testing",message:"Synthetic receipt integrity only")
        job.speakerVoiceIDs=["one":"voice-one","two":"voice-two"]
        job.speakerAssets=[:]
        for (speaker,bytes) in [("one",first),("two",second)] {
            let hash=LocalVisualEvidence.digest(bytes)
            job.speakerAssets?[speaker]=LocalVideoStudio.SpeakerAssets(voiceID:"voice-"+speaker,referenceFile:"reference-"+speaker+".wav",referenceSHA256:hash,previewFile:"preview-"+speaker+".wav",previewSHA256:hash)
            try bytes.write(to:folder.appendingPathComponent("reference-"+speaker+".wav"))
            try bytes.write(to:folder.appendingPathComponent("preview-"+speaker+".wav"))
        }
        try JSONEncoder().encode(job).write(to:folder.appendingPathComponent("job.json"))
        let studio=LocalVideoStudio(root:root,asrBundle:nil,f5Bundle:nil,speakerBundle:nil)
        XCTAssertEqual(studio.speakerAssetURL("one",preview:false)?.lastPathComponent,"reference-one.wav")
        XCTAssertEqual(studio.speakerAssetURL("two",preview:true)?.lastPathComponent,"preview-two.wav")
        XCTAssertNil(studio.speakerAssetURL("absent",preview:true))
        try first.write(to:folder.appendingPathComponent("preview-two.wav"))
        XCTAssertNil(studio.speakerAssetURL("two",preview:true))
        XCTAssertNotNil(studio.speakerAssetURL("one",preview:true))
        // Pair must be intact even if only its unchanged reference was requested.
        XCTAssertNil(studio.speakerAssetURL("two",preview:false))
        XCTAssertTrue(FileManager.default.fileExists(atPath:folder.appendingPathComponent("preview-two.wav").path))
        job.speakerAssets?["one"]=LocalVideoStudio.SpeakerAssets(voiceID:"voice-one",referenceFile:"reference-one.wav",referenceSHA256:LocalVisualEvidence.digest(first),previewFile:"preview-two.wav",previewSHA256:LocalVisualEvidence.digest(first))
        try JSONEncoder().encode(job).write(to:folder.appendingPathComponent("job.json"))
        let reopened=LocalVideoStudio(root:root,asrBundle:nil,f5Bundle:nil,speakerBundle:nil)
        XCTAssertNil(reopened.speakerAssetURL("one",preview:true))
        job.speakerAssets?["one"]=LocalVideoStudio.SpeakerAssets(voiceID:"wrong-voice",referenceFile:"reference-one.wav",referenceSHA256:LocalVisualEvidence.digest(first),previewFile:"preview-one.wav",previewSHA256:LocalVisualEvidence.digest(first))
        try JSONEncoder().encode(job).write(to:folder.appendingPathComponent("job.json"))
        XCTAssertNil(LocalVideoStudio(root:root,asrBundle:nil,f5Bundle:nil,speakerBundle:nil).speakerAssetURL("one",preview:true))
        job.speakerAssets=nil // Older job versions must remain readable without inventing a pair.
        try JSONEncoder().encode(job).write(to:folder.appendingPathComponent("job.json"))
        let legacy=LocalVideoStudio(root:root,asrBundle:nil,f5Bundle:nil,speakerBundle:nil)
        XCTAssertEqual(legacy.current?.id,id)
        XCTAssertNil(legacy.speakerAssetURL("one",preview:false))
    }
    @MainActor func testNewCandidateCannotReusePreviousSpeakersPreview() {
        let now = Date()
        var job = LocalVideoStudio.Job(id: UUID(), created: now, updated: now,
                                      stage: "Testing", message: "Synthetic state")
        job.referenceFile = "reference-one.wav"
        job.previewFile = "preview-one.wav"
        XCTAssertEqual(job.matchingPreviewFile, "preview-one.wav")
        job.selectReference("reference-two.wav")
        XCTAssertNil(job.previewFile)
        XCTAssertNil(job.matchingPreviewFile)
        // Older saved jobs may already contain an inconsistent pair.
        job.previewFile = "preview-one.wav"
        XCTAssertNil(job.matchingPreviewFile)
        job.previewFile = "preview-two.wav"
        XCTAssertEqual(job.matchingPreviewFile, "preview-two.wav")
    }
    @MainActor func testSimilarityCannotFollowChangedReferenceOrInvalidMetric() {
        let now=Date(), hash=String(repeating:"a",count:64)
        var job=LocalVideoStudio.Job(id:UUID(),created:now,updated:now,stage:"Testing",message:"Synthetic state")
        job.referenceFile="reference-one.wav";job.previewFile="preview-one.wav"
        let report=SpeakerSimilarityService.Report(schemaVersion:1,referenceSHA256:hash,generatedSHA256:hash,modelRevision:SpeakerSimilarityService.modelRevision,algorithm:"bundled-raw256-l2-cosine-v1",referenceSeconds:4,generatedSeconds:4,cosineSimilarity:0.4)
        job.similarity=LocalVideoStudio.Similarity(referenceFile:"reference-one.wav",previewFile:"preview-one.wav",measured:now,report:report)
        XCTAssertNotNil(job.matchingSimilarity)
        job.selectReference("reference-two.wav")
        XCTAssertNil(job.similarity);XCTAssertNil(job.matchingSimilarity)
        job.previewFile="preview-two.wav"
        job.similarity=LocalVideoStudio.Similarity(referenceFile:"reference-one.wav",previewFile:"preview-one.wav",measured:now,report:report)
        XCTAssertNil(job.matchingSimilarity)
        let invalid=SpeakerSimilarityService.Report(schemaVersion:1,referenceSHA256:hash,generatedSHA256:hash,modelRevision:SpeakerSimilarityService.modelRevision,algorithm:"bundled-raw256-l2-cosine-v1",referenceSeconds:4,generatedSeconds:4,cosineSimilarity:.nan)
        job.similarity=LocalVideoStudio.Similarity(referenceFile:"reference-two.wav",previewFile:"preview-two.wav",measured:now,report:invalid)
        XCTAssertNil(job.matchingSimilarity)
    }
    @MainActor func testReloadedSimilarityIsWithheldWhenRetainedBytesChange() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let now=Date(), id=UUID(), bytes=Data(repeating:1,count:44)
        let folder=root.appendingPathComponent(id.uuidString.lowercased())
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let hash=LocalVisualEvidence.digest(bytes)
        var job=LocalVideoStudio.Job(id:id,created:now,updated:now,stage:"Testing",message:"Hash-binding test only")
        job.referenceFile="reference-one.wav";job.previewFile="preview-one.wav"
        let report=SpeakerSimilarityService.Report(schemaVersion:1,referenceSHA256:hash,generatedSHA256:hash,modelRevision:SpeakerSimilarityService.modelRevision,algorithm:"bundled-raw256-l2-cosine-v1",referenceSeconds:4,generatedSeconds:4,cosineSimilarity:0.4)
        job.similarity=LocalVideoStudio.Similarity(referenceFile:"reference-one.wav",previewFile:"preview-one.wav",measured:now,report:report)
        try bytes.write(to:folder.appendingPathComponent("reference-one.wav"))
        try bytes.write(to:folder.appendingPathComponent("preview-one.wav"))
        try JSONEncoder().encode(job).write(to:folder.appendingPathComponent("job.json"))
        let studio=LocalVideoStudio(root:root,asrBundle:nil,f5Bundle:nil,speakerBundle:nil)
        XCTAssertNotNil(studio.validatedSimilarity())
        try Data(repeating:2,count:44).write(to:folder.appendingPathComponent("preview-one.wav"))
        XCTAssertNil(studio.validatedSimilarity())
        let reopened=LocalVideoStudio(root:root,asrBundle:nil,f5Bundle:nil,speakerBundle:nil)
        XCTAssertNil(reopened.validatedSimilarity())
        XCTAssertTrue(FileManager.default.fileExists(atPath:folder.appendingPathComponent("preview-one.wav").path))
    }
    func testMissingFirstWordFailsTenPercentGate() {
        XCTAssertGreaterThan(LocalStudioEvidence.wordErrorRate(expected: "I found a strange device near the portal.", actual: "Found a strange device near the portal."), 0.1)
        XCTAssertEqual(LocalStudioEvidence.wordErrorRate(expected: "Hello, WORLD!", actual: "hello world"), 0)
    }
    func testTranscriptBoundsAndAnnotations() {
        XCTAssertFalse(LocalStudioEvidence.usableTranscript("♪ some music here"))
        XCTAssertFalse(LocalStudioEvidence.usableTranscript("[applause] then words"))
        XCTAssertFalse(LocalStudioEvidence.usableTranscript("hello"))
        XCTAssertTrue(LocalStudioEvidence.usableTranscript("Three ordinary spoken words."))
    }
    func testWindowsAreBoundedAndDoNotOverrunSource() {
        XCTAssertTrue(LocalStudioEvidence.windows(duration: .nan).isEmpty)
        XCTAssertTrue(LocalStudioEvidence.windows(duration: 1801).isEmpty)
        for duration in [3.0, 7.5, 17, 1800] {
            let rows = LocalStudioEvidence.windows(duration: duration)
            XCTAssertFalse(rows.isEmpty)
            XCTAssertLessThanOrEqual(rows.count, 300)
            XCTAssertTrue(rows.allSatisfy { $0.start >= 0 && $0.seconds >= 3 && $0.seconds <= 8 && $0.start + $0.seconds <= duration })
        }
    }
}
