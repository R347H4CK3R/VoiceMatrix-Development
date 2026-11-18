import XCTest
import CryptoKit
@testable import VocalSeparationHarness

final class SeparationInferenceChecks:XCTestCase {
    private var fixture:URL {Bundle(for:Self.self).resourceURL!.appendingPathComponent("Fixtures")}
    private func floats(_ name:String) throws -> [Float] {
        let data=try Data(contentsOf:fixture.appendingPathComponent("Reference/"+name+".f32"))
        guard data.count%4==0,data.count<=5_000_000 else {throw NSError(domain:"fixture",code:1)}
        return data.withUnsafeBytes {raw in (0..<data.count/4).map {Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)))}}
    }
    private func parity(_ actual:[Float],_ name:String) throws {
        let expected=try floats(name);XCTAssertEqual(actual.count,expected.count)
        XCTAssertTrue(actual.allSatisfy(\.isFinite))
        guard actual.count==expected.count else {return}
        let delta=zip(actual,expected).map{Double($0)-Double($1)}
        let maximum=delta.map(abs).max() ?? 0
        let rms=sqrt(delta.reduce(0){$0+$1*$1}/Double(delta.count))
        print("NATIVE_SEPARATION_PARITY \(name) frames=\(actual.count) max=\(maximum) rms=\(rms)")
        // Fixed before native run. Float32 CPU architecture differences are expected;
        // bounds remain far below normalized-audio level and the separation improvement.
        XCTAssertLessThan(maximum,0.002)
        XCTAssertLessThan(rms,0.0002)
    }
    func testRealPinnedModelsMatchIndependentKnownMixtureReference() async throws {
        let modelRoot=fixture.appendingPathComponent("Models")
        try VocalSeparationAssets.validate(root:modelRoot)
        let cache=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:false)
        defer {try? FileManager.default.removeItem(at:cache)}
        let left=try floats("left"),right=try floats("right"),before=left
        let engine=try VocalSeparationEngine(modelRoot:modelRoot,cache:cache)
        let result=try await engine.separate(left:left,right:right)
        await engine.close()
        try parity(result.vocalsLeft,"vocals-left");try parity(result.vocalsRight,"vocals-right")
        try parity(result.accompanimentLeft,"accompaniment-left");try parity(result.accompanimentRight,"accompaniment-right")
        XCTAssertEqual(left,before)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:cache.path).isEmpty)
        let speech=try floats("speech")
        let beforeError=zip(left,speech).reduce(0.0){$0+pow(Double($1.0-$1.1),2)}
        let afterError=zip(result.vocalsLeft,speech).reduce(0.0){$0+pow(Double($1.0-$1.1),2)}
        print("NATIVE_SEPARATION_KNOWN_MIX errorBefore=\(beforeError) errorAfter=\(afterError)")
        XCTAssertLessThan(afterError,beforeError*0.8,"Fixed speech+instrumental surrogate must demonstrate real separation, not an identity mask")
        do {_ = try await engine.separate(left:left,right:right);XCTFail("Closed engine ran")} catch {}
    }
    /// Test-only WAV construction, independent of the production result writer.
    private func fixtureWAV(left:[Float],right:[Float]) -> Data {
        precondition(left.count==right.count)
        var bytes=Data()
        func text(_ s:String) {bytes.append(contentsOf:s.utf8)}
        func word<T:FixedWidthInteger>(_ v:T) {var little=v.littleEndian;withUnsafeBytes(of:&little){bytes.append(contentsOf:$0)}}
        text("RIFF");word(UInt32(36+left.count*8));text("WAVEfmt ");word(UInt32(16))
        word(UInt16(3));word(UInt16(2));word(UInt32(44100));word(UInt32(352800));word(UInt16(8));word(UInt16(32))
        text("data");word(UInt32(left.count*8))
        for i in left.indices {word(left[i].bitPattern);word(right[i].bitPattern)}
        return bytes
    }
    private func interleave(_ left:[Float],_ right:[Float]) -> [Float] {
        precondition(left.count==right.count)
        return left.indices.flatMap{[left[$0],right[$0]]}
    }
    func testWholeFileImportInferencePublicationAndReloadPreserveOriginal() async throws {
        let workspace=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        let cache=workspace.appendingPathComponent("Cache",isDirectory:true)
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:workspace)}
        let left=try floats("left"),right=try floats("right")
        let originalBytes=fixtureWAV(left:left,right:right)
        let originalSHA=SHA256.hash(data:originalBytes).map{String(format:"%02x",$0)}.joined()
        let originalURL=workspace.appendingPathComponent("Known-mixture.wav")
        try originalBytes.write(to:originalURL,options:.withoutOverwriting)
        let store=SeparationStore(root:workspace.appendingPathComponent("Results",isDirectory:true))
        let imported=try store.copyInput(originalURL)
        XCTAssertNotEqual(imported.url,originalURL)
        XCTAssertEqual(imported.sha,originalSHA)
        let decoded=try SeparationAudioImport.decode(imported.url)
        XCTAssertEqual(decoded.left,left);XCTAssertEqual(decoded.right,right)

        // One additional actual neural inference, not a mocked separator or mask.
        let engine=try VocalSeparationEngine(modelRoot:fixture.appendingPathComponent("Models"),cache:cache)
        let stems:VocalSeparationDSP.Stems
        do {stems=try await engine.separate(left:decoded.left,right:decoded.right)}
        catch {await engine.close();throw error}
        await engine.close()
        try parity(stems.vocalsLeft,"vocals-left");try parity(stems.vocalsRight,"vocals-right")
        try parity(stems.accompanimentLeft,"accompaniment-left");try parity(stems.accompanimentRight,"accompaniment-right")
        let vocals=interleave(stems.vocalsLeft,stems.vocalsRight)
        let backing=interleave(stems.accompanimentLeft,stems.accompanimentRight)
        let first=try store.publish(vocals:vocals,accompaniment:backing,inputName:"Known-mixture.wav",inputSHA256:imported.sha)
        let firstVocalBytes=try Data(contentsOf:first.vocals),firstBackingBytes=try Data(contentsOf:first.accompaniment)
        // A second publication exercises unique identities without spending another inference.
        let second=try store.publish(vocals:vocals,accompaniment:backing,inputName:"Known-mixture.wav",inputSHA256:imported.sha)
        XCTAssertNotEqual(first.id,second.id)
        XCTAssertEqual(Set([first.vocals,first.accompaniment,second.vocals,second.accompaniment].map{$0.lastPathComponent}).count,4)
        let reopened=SeparationStore(root:store.root)
        let recovered=try reopened.results()
        XCTAssertEqual(Set(recovered.map(\.id)),Set([first.id,second.id]))
        for result in recovered {
            XCTAssertEqual(result.frames,left.count)
            XCTAssertEqual(result.receipt.inputSHA256,originalSHA)
            XCTAssertEqual(result.receipt.modelSHA256,VocalSeparationAssets.models.mapValues{$0.sha256})
            XCTAssertTrue(try SeparationStore.validWAV(result.vocals,frames:left.count,sha:result.receipt.vocalsSHA256))
            XCTAssertTrue(try SeparationStore.validWAV(result.accompaniment,frames:left.count,sha:result.receipt.accompanimentSHA256))
            let savedVocals=try SeparationAudioImport.decode(result.vocals)
            let savedBacking=try SeparationAudioImport.decode(result.accompaniment)
            XCTAssertEqual(savedVocals.left,stems.vocalsLeft.map{$0*result.gain})
            XCTAssertEqual(savedVocals.right,stems.vocalsRight.map{$0*result.gain})
            XCTAssertEqual(savedBacking.left,stems.accompanimentLeft.map{$0*result.gain})
            XCTAssertEqual(savedBacking.right,stems.accompanimentRight.map{$0*result.gain})
        }
        XCTAssertEqual(try Data(contentsOf:originalURL),originalBytes)
        XCTAssertEqual(try Data(contentsOf:imported.url),originalBytes)
        XCTAssertEqual(try Data(contentsOf:first.vocals),firstVocalBytes)
        XCTAssertEqual(try Data(contentsOf:first.accompaniment),firstBackingBytes)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:cache.path).isEmpty)
        let children=try FileManager.default.contentsOfDirectory(atPath:store.root.path)
        XCTAssertFalse(children.contains{$0.hasPrefix(".staging-")})
        print("NATIVE_SEPARATION_END_TO_END frames=\(left.count) actualInference=1 durablePairs=2 uniqueStemFiles=4 originalAndCopiedInputUnchanged=true reloadHashesVerified=true")
    }
    func testCorruptOrUnpinnedModelsFailClosed() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
        defer {try? FileManager.default.removeItem(at:folder)}
        for name in ["vocals.onnx","accompaniment.onnx"] {try Data("not a model".utf8).write(to:folder.appendingPathComponent(name))}
        XCTAssertThrowsError(try VocalSeparationAssets.validate(root:folder))
    }
}
