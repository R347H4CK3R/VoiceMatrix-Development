import XCTest
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
    func testCorruptOrUnpinnedModelsFailClosed() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
        defer {try? FileManager.default.removeItem(at:folder)}
        for name in ["vocals.onnx","accompaniment.onnx"] {try Data("not a model".utf8).write(to:folder.appendingPathComponent(name))}
        XCTAssertThrowsError(try VocalSeparationAssets.validate(root:folder))
    }
}
