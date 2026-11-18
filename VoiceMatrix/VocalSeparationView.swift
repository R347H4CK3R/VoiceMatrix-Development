#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class VocalSeparationStudio: ObservableObject {
    @Published private(set) var busy=false
    @Published private(set) var cancelling=false
    @Published private(set) var inputName=""
    @Published private(set) var acceptedClipID:UUID?
    @Published private(set) var message="Choose an audio clip of 10 seconds or less. Nothing is uploaded."
    @Published private(set) var results:[SeparationStore.Result]=[]
    private var input:URL?
    private var inputSHA=""
    private var work:Task<Void,Never>?
    private var active=true
    private let store=SeparationStore.standard
    var models:URL? {Bundle.main.resourceURL?.appendingPathComponent("Separation",isDirectory:true)}
    var modelsPresent:Bool {
        guard let models else {return false}
        return ["vocals.onnx","accompaniment.onnx"].allSatisfy{FileManager.default.fileExists(atPath:models.appendingPathComponent($0).path)}
    }
    var hasInput:Bool {input != nil}
    func setActive(_ value:Bool) {active=value;if !value {cancel()}}
    func cancel() {guard busy else{return};cancelling=true;message="Stopping safely. The current inference must finish before audio is released.";work?.cancel()}
    func refresh(audio:AudioStore) {
        guard !busy,active,let lease=audio.claimProcessing() else{return}
        busy=true
        work=Task {
            defer {audio.releaseProcessing(lease);busy=false;work=nil}
            do {
                let store=self.store
                let worker=Task.detached {try store.results()}
                results=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
            } catch {message="Saved results could not be checked. No files were removed."}
        }
    }
    func importAudio(_ source:URL,audio:AudioStore) {
        guard !busy,active,let lease=audio.claimProcessing() else{return}
        busy=true;cancelling=false;message="Copying and checking the complete clip…"
        let name=String(source.lastPathComponent.prefix(120)),store=self.store
        work=Task {
            defer {audio.releaseProcessing(lease);busy=false;cancelling=false;work=nil}
            do {
                let worker=Task.detached {() throws -> (URL,String) in
                    let scoped=source.startAccessingSecurityScopedResource();defer{if scoped {source.stopAccessingSecurityScopedResource()}}
                    let copied=try store.copyInput(source)
                    // Retain a completed source copy even when decoding/cancellation fails.
                    _=try SeparationAudioImport.decode(copied.url)
                    guard try SeparationStore.digest(copied.url,maximum:64*1024*1024)==copied.sha else {throw SeparationStore.Failure.unsafe}
                    return (copied.url,copied.sha)
                }
                let copied=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation();input=copied.0;inputSHA=copied.1;inputName=name
                message="Complete clip imported. Tap Separate to create two stems on this iPhone."
            } catch is CancellationError {message="Stopped. Original audio and earlier results were kept."}
            catch {message="Could not import this clip. Use a complete audio file up to 10 seconds and 64 MiB, mono or stereo. No original was changed."}
        }
    }
    @discardableResult func acceptClip(_ clip:SeparationClipHandoff.Input,audio:AudioStore) -> Bool {
        guard !busy,active,let lease=audio.claimProcessing() else{return false}
        busy=true;cancelling=false
        message="Checking the selected retained-media clip…"
        work=Task {
            defer {audio.releaseProcessing(lease);busy=false;cancelling=false;work=nil}
            do {
                let worker=Task.detached {
                    try SeparationClipHandoff.validate(clip)
                    let decoded=try SeparationAudioImport.decode(clip.url)
                    guard decoded.left.count==clip.frames else {throw SeparationStore.Failure.unsafe}
                    try SeparationClipHandoff.validate(clip)
                }
                try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation();guard active else{return}
                input=clip.url;inputSHA=clip.sha256;acceptedClipID=clip.id
                inputName=String(format:"Retained clip %.3f–%.3f s",clip.start,clip.start+Double(clip.frames)/44100)
                message="Selected short clip ready. Tap Separate to run experimental separation. The entire source is not being processed."
            } catch {message="Selected clip could not be verified. No separation started; original files were kept."}
        }
        return true
    }
    func run(audio:AudioStore) {
        guard !busy,active,let source=input,let models,modelsPresent,let lease=audio.claimProcessing() else{return}
        busy=true;cancelling=false;audio.stop();message="Separating vocals and accompaniment on this iPhone…"
        let store=self.store,name=inputName,sha=inputSHA
        work=Task {
            defer {audio.releaseProcessing(lease);busy=false;cancelling=false;work=nil}
            do {
                let worker=Task.detached {() async throws -> SeparationStore.Result in
                    guard try SeparationStore.digest(source,maximum:64*1024*1024)==sha else {throw SeparationStore.Failure.unsafe}
                    let decoded=try SeparationAudioImport.decode(source)
                    guard try SeparationStore.digest(source,maximum:64*1024*1024)==sha else {throw SeparationStore.Failure.unsafe}
                    let cache=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("VocalSeparation",isDirectory:true)
                    try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
                    let engine=try VocalSeparationEngine(modelRoot:models,cache:cache)
                    do {
                        let stems=try await engine.separate(left:decoded.left,right:decoded.right)
                        await engine.close()
                        try Task.checkCancellation()
                        guard stems.vocalsLeft.count==decoded.left.count,stems.vocalsRight.count==decoded.left.count,
                              stems.accompanimentLeft.count==decoded.left.count,stems.accompanimentRight.count==decoded.left.count else {throw SeparationStore.Failure.invalid}
                        var vocals:[Float]=[],backing:[Float]=[]
                        vocals.reserveCapacity(decoded.left.count*2);backing.reserveCapacity(decoded.left.count*2)
                        for i in decoded.left.indices {
                            if i%8192==0 {try Task.checkCancellation()}
                            vocals.append(stems.vocalsLeft[i]);vocals.append(stems.vocalsRight[i])
                            backing.append(stems.accompanimentLeft[i]);backing.append(stems.accompanimentRight[i])
                        }
                        return try store.publish(vocals:vocals,accompaniment:backing,inputName:name,inputSHA256:sha)
                    } catch {await engine.close();throw error}
                }
                let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                // Atomic pair publication wins a cancellation arriving after commit.
                results.insert(result,at:0)
                message=result.gain<1 ? "Both stems saved. A shared gain reduction prevented clipping; the original is unchanged." : "Both stems saved. Your original is unchanged. Listen to check separation quality."
            } catch is CancellationError {message="Stopped. No partial pair was published; previous results and original audio were kept."}
            catch {message="Separation could not finish. Model verification, clip format, or storage checks failed. Previous results and original audio were kept."}
        }
    }
}

struct VocalSeparationView: View {
    @EnvironmentObject private var audio:AudioStore
    @Environment(\.scenePhase) private var scene
    @StateObject private var studio=VocalSeparationStudio()
    @State private var importing=false
    private let initialClip:SeparationClipHandoff.Input?
    @State private var loadedInitialClip=false
    init(initialClip:SeparationClipHandoff.Input? = nil) {self.initialClip=initialClip}
    private var unavailable:Bool {studio.busy || audio.processingInUse || audio.microphoneInUse}
    var body: some View {
        Form {
            Section("Experimental · on this iPhone") {
                Text("Separate vocals and accompaniment from a complete clip up to 10 seconds. Quality varies: instruments may leak into vocals and voices may remain in the backing track.")
                Text("This model removes high frequencies above about 11 kHz from both stems.").font(.caption)
                Text("No upload, training, voice identity or character creation. Mono is duplicated to stereo; stereo channels are retained at 44.1 kHz.").font(.caption)
                if !studio.modelsPresent {Text("The pinned separation models are missing from this build. Separation is unavailable.").foregroundStyle(.orange)}
            }
            Section("Choose audio") {
                Button(studio.inputName.isEmpty ? "Import audio":studio.inputName){importing=true}
                    .disabled(unavailable).accessibilityIdentifier("separation-import")
                Button("Separate vocals and accompaniment"){studio.run(audio:audio)}
                    .disabled(unavailable || !studio.hasInput || !studio.modelsPresent).accessibilityIdentifier("separation-run")
                if studio.busy {
                    ProgressView()
                    Button("Cancel",role:.cancel){studio.cancel()}.disabled(studio.cancelling).accessibilityIdentifier("separation-cancel")
                }
                Text(studio.message).accessibilityIdentifier("separation-status")
            }
            ForEach(studio.results) {result in
                Section(result.receipt.inputName) {
                    Text("Experimental separation · \(Double(result.frames)/44100,specifier:"%.2f") seconds").font(.caption)
                    if result.gain<1 {Text("Both stems use the same gain of \(result.gain,specifier:"%.5f") to prevent clipping.").font(.caption)}
                    Text("Vocals").font(.headline)
                    AudioActions(url:result.vocals,accessibilityPrefix:"separation-vocals-"+result.id.uuidString).disabled(unavailable)
                    NavigationLink("Use vocals for speaker references") {
                        LocalVideoStudioView(initialSeparatedVocals: result)
                    }.disabled(unavailable).accessibilityIdentifier("separation-reference-"+result.id.uuidString)
                    Text("Accompaniment").font(.headline)
                    AudioActions(url:result.accompaniment,accessibilityPrefix:"separation-backing-"+result.id.uuidString).disabled(unavailable)
                }
            }
        }.navigationTitle("Separate vocals").accessibilityIdentifier("separation-screen")
        .fileImporter(isPresented:$importing,allowedContentTypes:[.audio]) {result in
            if case .success(let url)=result {studio.importAudio(url,audio:audio)}
        }
        .onAppear{
            studio.setActive(scene == .active)
            if initialClip != nil {loadInitialClipIfReady()}
            else {studio.refresh(audio:audio)}
        }
        .onDisappear{studio.setActive(false);if studio.acceptedClipID != initialClip?.id {loadedInitialClip=false}}
        .onChange(of:scene){_,value in
            studio.setActive(value == .active)
            if value != .active,studio.acceptedClipID != initialClip?.id {loadedInitialClip=false}
            if value == .active {loadInitialClipIfReady()}
        }
        .onChange(of:studio.busy){_,busy in if !busy {loadInitialClipIfReady()}}
        .onChange(of:audio.processingInUse){_,busy in if !busy {loadInitialClipIfReady()}}
    }
    private func loadInitialClipIfReady() {
        guard scene == .active,!loadedInitialClip,!studio.busy,let initialClip else{return}
        loadedInitialClip=studio.acceptClip(initialClip,audio:audio)
    }
}
#endif
