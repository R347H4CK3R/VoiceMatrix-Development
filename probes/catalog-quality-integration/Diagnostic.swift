import Foundation
import CryptoKit

/// Uses actual CharacterLibrary generation, recognition, ownership, history and deletion.
/// Known licensed diagnostic references, not user files. No injected verification results.
@main struct CatalogIntegrationDiagnostic {
    enum Failure: Error { case assertion, timeout }
    static func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf:url)).map { String(format:"%02x",$0) }.joined()
    }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.assertion }
        let resources=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
        let base=URL(fileURLWithPath:CommandLine.arguments[2]).standardizedFileURL
        let support=base.appendingPathComponent("integration-support")
        let library=CharacterLibrary(supportRoot:support,f5Bundle:resources.appendingPathComponent("F5TTS"))
        let audio=AudioStore(recordingRoot:base.appendingPathComponent("Recordings"))
        let speech=SpeechStudio()
        let text="Please close the window and bring the notebook."
        let positive="local-fe605440-0254-491c-8c43-03de2e1f8a2a-s1"
        let negative="local-fe605440-0254-491c-8c43-03de2e1f8a2a-s2"
        @MainActor func settle() async throws {
            let deadline=Date().addingTimeInterval(600)
            while library.busy {
                guard Date()<deadline else { library.cancel();throw Failure.timeout }
                try await Task.sleep(for:.milliseconds(50))
            }
            guard !audio.processingInUse else { throw Failure.assertion }
        }
        for name in ["positive","negative"] {
            let owner=try await library.beginLocalGeneration()
            do { try await library.importLocalGeneratedCollection(base.appendingPathComponent(name),owner:owner) }
            catch { library.endLocalGeneration(owner);throw error }
            library.endLocalGeneration(owner)
        }
        let references=Dictionary(uniqueKeysWithValues:library.profiles.map { ($0.id,$0.referenceSHA256) })
        guard references.count==2 else { throw Failure.assertion }
        library.selectedID=positive;library.speak(text,audio:audio,studio:speech);try await settle()
        guard let good=library.output,library.pendingSpeech==nil,library.outputCharacterID==positive else { throw Failure.assertion }
        let goodHash=try digest(good)
        let goodReceipt=try JSONDecoder().decode(CatalogSpeechQuality.Result.self,from:Data(contentsOf:good.deletingLastPathComponent().appendingPathComponent("word-check.json")))
        guard goodReceipt.verified,goodReceipt.audioSHA256==goodHash else { throw Failure.assertion }
        library.selectedID=negative;library.speak(text,audio:audio,studio:speech);try await settle()
        guard let rejected=library.pendingSpeech,library.pendingSpeechMatchesSelection,
              library.output==good,try digest(good)==goodHash,library.outputCharacterID==positive else { throw Failure.assertion }
        let rejection=try JSONDecoder().decode(CatalogSpeechQuality.Result.self,from:Data(contentsOf:rejected.audio.deletingLastPathComponent().appendingPathComponent("word-check.json")))
        guard !rejection.verified,rejection.wordErrorRate==0.125,rejection.audioSHA256==(try digest(rejected.audio)) else { throw Failure.assertion }
        library.selectedID=positive;guard !library.pendingSpeechMatchesSelection else { throw Failure.assertion }
        library.selectedID=negative
        library.speak(text,audio:audio,studio:speech)
        let deadline=Date().addingTimeInterval(600)
        while library.busy && library.pendingSpeech?.audio==rejected.audio {
            guard Date()<deadline else { library.cancel();throw Failure.timeout }
            try await Task.sleep(for:.milliseconds(10))
        }
        guard library.busy,let checking=library.pendingSpeech,checking.audio != rejected.audio else { throw Failure.assertion }
        // An active generation must not let explicit deletion remove prior checked output.
        guard let goodID=UUID(uuidString:good.deletingLastPathComponent().lastPathComponent) else { throw Failure.assertion }
        library.deleteSpeechHistory(goodID)
        guard FileManager.default.fileExists(atPath:good.path) else { throw Failure.assertion }
        library.cancel();try await settle()
        guard let canceled=library.pendingSpeech,canceled.audio==checking.audio,
              library.output==good,try digest(good)==goodHash,
              canceled.reason.lowercased().contains("stopped") else { throw Failure.assertion }
        let canceledReceipt=try JSONDecoder().decode(CatalogSpeechQuality.Result.self,from:Data(contentsOf:canceled.audio.deletingLastPathComponent().appendingPathComponent("word-check.json")))
        guard !canceledReceipt.verified else { throw Failure.assertion }
        let reload=CharacterLibrary(supportRoot:support,f5Bundle:resources.appendingPathComponent("F5TTS"))
        await reload.loadAndRefresh()
        guard reload.speechHistory.count==3,reload.speechHistory.allSatisfy({!$0.verified}),reload.output==nil,
              Dictionary(uniqueKeysWithValues:reload.profiles.map { ($0.id,$0.referenceSHA256) })==references else { throw Failure.assertion }
        guard let canceledID=UUID(uuidString:canceled.audio.deletingLastPathComponent().lastPathComponent) else { throw Failure.assertion }
        // Preserve diagnostic outputs independently before explicit owner-style deletion.
        for (name,url) in [("positive-output",good),("rejected-output",rejected.audio),("canceled-output",canceled.audio)] {
            try FileManager.default.copyItem(at:url,to:base.appendingPathComponent(name+".wav"))
            try FileManager.default.copyItem(at:url.deletingLastPathComponent().appendingPathComponent("word-check.json"),to:base.appendingPathComponent(name+"-receipt.json"))
            try FileManager.default.copyItem(at:url.deletingLastPathComponent().appendingPathComponent("request.json"),to:base.appendingPathComponent(name+"-request.json"))
        }
        library.deleteSpeechHistory(canceledID)
        guard library.pendingSpeech==nil,!FileManager.default.fileExists(atPath:canceled.audio.path),library.output==good else { throw Failure.assertion }
        library.deleteSpeechHistory(goodID)
        guard library.output==nil,library.outputCharacterID.isEmpty,library.outputReferenceHash.isEmpty,
              FileManager.default.fileExists(atPath:rejected.audio.path),library.profiles.count==2 else { throw Failure.assertion }
        let finalStore=CharacterFolderStore(root:support.appendingPathComponent("CharacterReferences",isDirectory:true))
        let finalProfiles=try await finalStore.profiles()
        guard Dictionary(uniqueKeysWithValues:finalProfiles.map { ($0.id,$0.referenceSHA256) })==references else { throw Failure.assertion }
        for profile in finalProfiles {
            let file=try await finalStore.referenceURL(id:profile.id)
            guard try digest(file)==references[profile.id] else { throw Failure.assertion }
        }
        let result:[String:Any] = ["actualCatalogPositivePromotion":true,"actualCatalogRejectedPreservesPrevious":true,"actualCatalogCancellationRetained":true,"busyDeletionBlocked":true,"reloadUnverified":true,"deleteClearsBindings":true,"referenceProfilesPreserved":true,"physicalDeviceVerified":false,"uiPlaybackExportVerified":false,"positiveSHA256":goodHash,"rejectedSHA256":rejection.audioSHA256]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("catalog-integration-results.json"))
    }
}
