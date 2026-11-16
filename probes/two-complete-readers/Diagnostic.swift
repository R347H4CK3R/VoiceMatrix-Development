import Foundation
import AVFoundation
import CryptoKit
import Metal
@preconcurrency import CoreML
import FluidAudio

/// Diagnostic-only two-profile extension of the existing real-coordinator harness.
/// Every imported profile must generate fresh word-checked speech; no injected speaker IDs.
@main struct LocalStudioDiagnostic {
    enum Failure: Error { case arguments, fixture, timeout, pipeline, evidence, preservation, sourceTranscript }
    struct SpeechCheck: Codable {
        let voiceID: String
        let referenceSHA256: String
        let newSpeechSHA256: String
        let newSpeechWordErrorRate: Double
        let file: String
        let asrFile: String
        let transcript: String
    }
    struct Report: Codable {
        let sourceCommit: String
        let fixtureKind: String
        let visualFrameCount: Int
        let fixtureSHA256: String
        let sourceRetainedSHA256: String
        let importedIDs: [String]
        let events: [LocalVideoStudio.Event]
        let cancellationRetainedSource: Bool
        let resumeCompleted: Bool
        let freshStoreReloadPreservedIDs: Bool
        let priorProfilePreserved: Bool
        let newSpeeches: [SpeechCheck]
        let evidenceFiles: [String]
        let physicalIPhoneVerified = false
        let likenessVerified = false
        let characterIdentificationVerified = false
        let pipelineKind = "Actual production local coordinator on macOS; fixture provenance recorded separately"
    }
    static func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format:"%02x",$0) }.joined()
    }
    /// Diagnostic-only raw recognition after a rejected production result.
    /// Never converts a rejection into a passing generation result.
    static func inspectRejectedSpeech(_ file:URL, resources:URL, destination:URL) async throws {
        let config=MLModelConfiguration();config.computeUnits = .cpuAndNeuralEngine
        let manager=AsrManager(config:ASRConfig(parallelChunkConcurrency:1),models:
            try AsrModels.loadLocal(from:resources.appendingPathComponent("ParakeetASR"),version:.v3,configuration:config,
                                    encoderPrecision:.int8V2,encoderComputeUnits:.cpuAndNeuralEngine))
        do {
            var decoder=try TdtDecoderState(decoderLayers:2)
            let result=try await manager.transcribe(file,decoderState:&decoder)
            let scores=result.tokenTimings?.map(\.confidence) ?? []
            let text=result.text.trimmingCharacters(in:.whitespacesAndNewlines)
            let evidence:[String:Any] = ["inputSHA256":try digest(file),"rawText":text,
                "usableTranscript":LocalStudioEvidence.usableTranscript(text),
                "hasTokenTimings":result.tokenTimings != nil,"tokenScores":scores.map { String($0) },
                "tokenMeanAdmitted":BundledASRPolicy.admittedTokenMean(scores) != nil,
                "diagnosticOnly":true,"productionRejectionPreserved":true]
            try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:destination,options:.atomic)
            await manager.cleanup()
        } catch { await manager.cleanup();throw error }
    }
    @MainActor static func settle(_ studio: LocalVideoStudio, seconds: Double = 1200) async throws {
        let deadline=Date().addingTimeInterval(seconds)
        while studio.busy {
            guard Date()<deadline else { studio.cancel(); throw Failure.timeout }
            try await Task.sleep(for:.milliseconds(100))
        }
    }
    @MainActor static func main() async throws {
        guard [8,9].contains(CommandLine.arguments.count), MTLCreateSystemDefaultDevice() != nil else { throw Failure.arguments }
        let resources=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let fixture=URL(fileURLWithPath:CommandLine.arguments[2])
        let priorCollection=URL(fileURLWithPath:CommandLine.arguments[3],isDirectory:true)
        let work=URL(fileURLWithPath:CommandLine.arguments[4],isDirectory:true).resolvingSymlinksInPath()
        let report=URL(fileURLWithPath:CommandLine.arguments[5])
        let commit=CommandLine.arguments[6]
        let fixtureKind=CommandLine.arguments[7]
        guard ["audio","video"].contains(fixtureKind) else { throw Failure.arguments }
        guard commit.range(of:"^[a-f0-9]{40}$",options:.regularExpression) != nil,
              !FileManager.default.fileExists(atPath:work.path) else { throw Failure.arguments }
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        let fixtureAsset=AVURLAsset(url:fixture)
        let seconds=try await fixtureAsset.load(.duration).seconds
        let audioTracks=try await fixtureAsset.loadTracks(withMediaType:.audio)
        let videoTracks=try await fixtureAsset.loadTracks(withMediaType:.video)
        guard (8...60).contains(seconds),audioTracks.count==1,
              videoTracks.count == (fixtureKind == "video" ? 1 : 0) else { throw Failure.fixture }
        if fixtureKind == "audio" {
            let decoded=try AVAudioFile(forReading:fixture)
            guard decoded.processingFormat.channelCount==1 else { throw Failure.fixture }
        }
        let fixtureHash=try digest(fixture)
        guard CommandLine.arguments.count == 9 else { throw Failure.arguments }
        let sourceRoot=fixture.deletingLastPathComponent()
        let combinedExpected=try String(contentsOfFile:CommandLine.arguments[8],encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
        var sourceChecks: [[String:Any]]=[]
        var sourceTexts: [String]=[]
        for index in 0..<2 {
            let original=sourceRoot.appendingPathComponent("original-\(index).wav")
            let expected=try String(contentsOf:sourceRoot.appendingPathComponent("original-\(index).txt"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
            guard !expected.isEmpty,expected.utf8.count<=8192 else { throw Failure.arguments }
            sourceTexts.append(expected)
            let originalHash=try digest(original)
            let recognizer=OnDeviceTranscription(bundle:resources.appendingPathComponent("ParakeetASR"))
            do {
                let actual=try await recognizer.transcribe(original)
                let wer=LocalStudioEvidence.wordErrorRate(expected:expected,actual:actual)
                guard let receipt=recognizer.lastEvidence else { throw Failure.sourceTranscript }
                sourceChecks.append(["index":index,"expected":expected,"actual":actual,"wordErrorRate":wer,"inputSHA256":originalHash,"asrInputSHA256":receipt.inputSHA256,"asrTranscriptSHA256":receipt.transcriptSHA256])
                try JSONSerialization.data(withJSONObject:sourceChecks,options:[.prettyPrinted,.sortedKeys]).write(to:sourceRoot.appendingPathComponent("source-transcript-check.json"),options:.atomic)
                guard wer<=0.1,receipt.inputSHA256==originalHash else { throw Failure.sourceTranscript }
            } catch {
                try JSONSerialization.data(withJSONObject:["index":index,"inputSHA256":originalHash,"error":String(describing:error)],options:[.prettyPrinted,.sortedKeys]).write(to:sourceRoot.appendingPathComponent("source-transcript-error.json"),options:.atomic)
                throw error
            }
        }
        guard sourceTexts.joined(separator:" ")==combinedExpected else { throw Failure.sourceTranscript }
        let support=work.appendingPathComponent("Support",isDirectory:true)
        let store=CharacterFolderStore(root:support.appendingPathComponent("CharacterReferences",isDirectory:true))
        let prior=try await store.importCollection(at:priorCollection)
        guard prior.count==1 else { throw Failure.fixture }
        let priorID=prior[0].id,priorHash=prior[0].referenceSHA256
        let library=CharacterLibrary(supportRoot:support,f5Bundle:resources.appendingPathComponent("F5TTS"))
        await library.loadAndRefresh()
        let audio=AudioStore(recordingRoot:work.appendingPathComponent("Recordings",isDirectory:true))
        let speech=SpeechStudio()
        let studio=LocalVideoStudio(root:work.appendingPathComponent("Jobs",isDirectory:true),
            asrBundle:resources.appendingPathComponent("ParakeetASR"),
            f5Bundle:resources.appendingPathComponent("F5TTS"),
            speakerBundle:resources.appendingPathComponent("Diarization"))
        do {
            studio.start(fixture,authorized:true,library:library,audio:audio,speech:speech)
            let cancelDeadline=Date().addingTimeInterval(120)
            while studio.busy && studio.current?.sourceFile==nil {
                guard Date()<cancelDeadline else { throw Failure.timeout }
                try await Task.sleep(for:.milliseconds(10))
            }
            guard studio.busy, let job=studio.current,let name=job.sourceFile else { throw Failure.pipeline }
            studio.cancel()
            try await settle(studio)
            let retained=work.appendingPathComponent("Jobs/"+job.id.uuidString.lowercased()+"/"+name)
            guard try digest(retained)==fixtureHash, !audio.processingInUse, !library.busy else { throw Failure.preservation }
            studio.resume(library:library,audio:audio,speech:speech)
            try await settle(studio)
            guard studio.current?.completed == true,let completed=studio.current,
                  let ids=completed.speakerVoiceIDs,!ids.isEmpty, !audio.processingInUse,!library.busy else { throw Failure.pipeline }
            let reopenedStudio=LocalVideoStudio(root:work.appendingPathComponent("Jobs",isDirectory:true),asrBundle:nil,f5Bundle:nil,speakerBundle:nil)
            guard reopenedStudio.current?.id == completed.id else { throw Failure.preservation }
            for (speaker,id) in ids {
                guard completed.speakerAssets?[speaker]?.voiceID == id,
                      let reference=reopenedStudio.speakerAssetURL(speaker,preview:false),
                      let preview=reopenedStudio.speakerAssetURL(speaker,preview:true) else { throw Failure.evidence }
                let referenceAudio=try AVAudioFile(forReading:reference)
                let previewAudio=try AVAudioFile(forReading:preview)
                guard referenceAudio.length>0,previewAudio.length>0 else { throw Failure.evidence }
            }
            let folder=retained.deletingLastPathComponent()
            let files=try FileManager.default.contentsOfDirectory(atPath:folder.path)
            guard let visual=completed.visualEvidence,visual.sourceSHA256 == fixtureHash else { throw Failure.evidence }
            if fixtureKind == "video" {
                guard !visual.audioOnly,!visual.frames.isEmpty,visual.unavailableFrames == 0,
                      visual.frames.allSatisfy({ $0.lines.contains { $0.text.uppercased().contains("VISIBLE LABEL") && $0.text.uppercased().contains("DEMO") } }) else { throw Failure.evidence }
                for frame in visual.frames { _ = try LocalVisualEvidence.frameData(frame,folder:folder) }
            } else {
                guard visual.audioOnly,visual.frames.isEmpty else { throw Failure.evidence }
            }
            guard let similarity=completed.matchingSimilarity,
                  similarity.report.referenceSHA256 == (try digest(folder.appendingPathComponent(similarity.referenceFile))),
                  similarity.report.generatedSHA256 == (try digest(folder.appendingPathComponent(similarity.previewFile))) else { throw Failure.evidence }
            for prefix in ["similarity-","diarization-","quality-","transcription-evidence-","preview-asr-evidence-","preview-"] {
                guard files.contains(where:{$0.hasPrefix(prefix)}) else { throw Failure.evidence }
            }
            guard let preview=studio.preview else { throw Failure.evidence }
            let wave=try AVAudioFile(forReading:preview)
            guard wave.length>0,let buffer=AVAudioPCMBuffer(pcmFormat:wave.processingFormat,frameCapacity:AVAudioFrameCount(wave.length)) else { throw Failure.evidence }
            try wave.read(into:buffer)
            guard buffer.frameLength>0 else { throw Failure.evidence }
            let reloaded=CharacterLibrary(supportRoot:support,f5Bundle:resources.appendingPathComponent("F5TTS"))
            await reloaded.loadAndRefresh()
            let expected=Set(ids.values)
            guard expected.isSubset(of:Set(reloaded.profiles.map(\.id))),
                  reloaded.profiles.contains(where:{$0.id==priorID && $0.referenceSHA256==priorHash}),
                  try digest(retained)==fixtureHash,try digest(fixture)==fixtureHash else { throw Failure.preservation }
            let beforeCount=reloaded.profiles.count
            studio.resume(library:reloaded,audio:audio,speech:speech)
            try await settle(studio)
            guard reloaded.profiles.count==beforeCount else { throw Failure.preservation }
            // Generate new words through the reloaded production catalog, not the preview adapter.
            guard expected.count == 2 else { throw Failure.evidence }
            var newSpeeches: [SpeechCheck] = []
            for voiceID in expected.sorted() {
            reloaded.selectedID=voiceID
            let newText="Please close the window and bring the notebook."
            reloaded.speak(newText,audio:audio,studio:speech)
            let speechDeadline=Date().addingTimeInterval(600)
            while reloaded.busy {
                guard Date()<speechDeadline else { reloaded.cancel(); throw Failure.timeout }
                try await Task.sleep(for:.milliseconds(100))
            }
            guard let freshSpeech=reloaded.output,!reloaded.outputReferenceHash.isEmpty,!audio.processingInUse,
                  reloaded.outputCharacterID==reloaded.selectedID,
                  reloaded.profiles.first(where:{$0.id==reloaded.selectedID})?.referenceSHA256==reloaded.outputReferenceHash else { throw Failure.pipeline }
            let checkedReference=reloaded.outputReferenceHash
            // Preserve generated bytes before ASR, including failed/noSpeech checks.
            let finalSpeech=work.appendingPathComponent("new-speech-\(voiceID).wav")
            try FileManager.default.copyItem(at:freshSpeech,to:finalSpeech)
            let generated: [String:Any] = ["expectedText":newText,"sha256":try digest(finalSpeech),"recognitionVerified":false]
            try JSONSerialization.data(withJSONObject:generated,options:[.prettyPrinted,.sortedKeys]).write(to:work.appendingPathComponent("new-speech-attempt-\(voiceID).json"),options:.atomic)
            // beginLocalGeneration uses the real ownership fence and unloads warm F5 before ASR.
            let verificationOwner=try await reloaded.beginLocalGeneration()
            defer { reloaded.endLocalGeneration(verificationOwner) }
            let recognizer=OnDeviceTranscription(bundle:resources.appendingPathComponent("ParakeetASR"))
            let words:String
            do { words=try await recognizer.transcribe(freshSpeech) }
            catch {
                let rejection:[String:Any] = ["error":String(describing:error),"inputSHA256":try digest(finalSpeech),"expectedText":newText]
                try JSONSerialization.data(withJSONObject:rejection,options:[.prettyPrinted,.sortedKeys]).write(to:work.appendingPathComponent("new-speech-rejection-\(voiceID).json"),options:.atomic)
                do { try await inspectRejectedSpeech(finalSpeech,resources:resources,destination:work.appendingPathComponent("new-speech-raw-asr-\(voiceID).json")) }
                catch { try? String(describing:error).write(to:work.appendingPathComponent("raw-asr-error-\(voiceID).txt"),atomically:true,encoding:.utf8) }
                throw error
            }
            reloaded.endLocalGeneration(verificationOwner)
            let wer=LocalStudioEvidence.wordErrorRate(expected:newText,actual:words)
            try JSONSerialization.data(withJSONObject:["expectedText":newText,"actual":words,"wordErrorRate":wer,"inputSHA256":try digest(finalSpeech)],options:[.prettyPrinted,.sortedKeys]).write(to:work.appendingPathComponent("new-speech-words-\(voiceID).json"),options:.atomic)
            guard wer<=0.1,let detail=recognizer.lastEvidence,
                  detail.inputSHA256 == (try digest(freshSpeech)) else { throw Failure.evidence }
            try JSONEncoder().encode(detail).write(to:work.appendingPathComponent("new-speech-asr-\(voiceID).json"),options:.atomic)
            newSpeeches.append(SpeechCheck(voiceID:voiceID,referenceSHA256:checkedReference,newSpeechSHA256:try digest(finalSpeech),newSpeechWordErrorRate:wer,file:finalSpeech.lastPathComponent,asrFile:"new-speech-asr-\(voiceID).json",transcript:words))
            try JSONEncoder().encode(newSpeeches).write(to:work.appendingPathComponent("completed-speech-checks.json"),options:.atomic)
            }
            let result=Report(sourceCommit:commit,fixtureKind:fixtureKind,visualFrameCount:visual.frames.count,fixtureSHA256:fixtureHash,sourceRetainedSHA256:try digest(retained),importedIDs:expected.sorted(),events:completed.events,cancellationRetainedSource:true,resumeCompleted:true,freshStoreReloadPreservedIDs:true,priorProfilePreserved:true,newSpeeches:newSpeeches,evidenceFiles:files.sorted())
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(result).write(to:report,options:.atomic)
            print("Actual local coordinator completed with retained source, cancellation/resume and persisted imports. iPhone behavior and likeness are unverified.")
        } catch {
            // A failed native gate must expose the actual final stage in CI logs.
            if let job=studio.current {
                let lines = ["Local pipeline failed at stage: " + job.stage + "; status: " + job.message] + job.events.suffix(12).map { $0.stage + ": " + $0.message }
                try? FileHandle.standardError.write(contentsOf: Data((lines.joined(separator:"\n") + "\n").utf8))
            }
            studio.cancel()
            try? await settle(studio,seconds:120)
            if let job=studio.current { try? JSONEncoder().encode(job).write(to:report.deletingLastPathComponent().appendingPathComponent("failed-job.json"),options:.atomic) }
            throw error
        }
    }
}
