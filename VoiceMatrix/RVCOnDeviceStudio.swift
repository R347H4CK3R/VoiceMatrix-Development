#if os(iOS)
import Foundation
import Combine
import CryptoKit

@MainActor final class RVCOnDeviceStudio:ObservableObject {
    @Published private(set) var voiceName="No voice model installed"
    @Published private(set) var retrievalSupported=false
    @Published private(set) var defaultIndexRate:Float=0.75
    private var currentModelSHA:String?
    @Published var indexRate:Float=0.75
    @Published var refinePitch=false
    @Published var semitones:Double=0
    @Published private(set) var state=RVCPreviewState()
    @Published private(set) var installed:[RVCPreviewPack:URL]=[:]
    @Published private(set) var input:URL?
    @Published private(set) var inputName=""
    @Published private(set) var output:URL?
    @Published private(set) var outputName=""
    @Published private(set) var message="Install the encoder and diagnostic voice model, then import audio. Retrieval data is optional when its strength is zero."
    @Published private(set) var history:[RVCResultHistory.Receipt]=[]
    @Published private(set) var historyNotice=""
    private var historyRefresh:Task<Void,Never>?
    private enum HistoryFailure:Error {case completedButUnindexed}
    private var work:Task<Void,Never>?
    private var active=true
    init() {refresh();refreshHistory()}
    func refresh() {
        do {
            try RVCPreviewStore.prepare();installed=try RVCPreviewStore.locations()
            voiceName="No voice model installed";retrievalSupported=false
            if let folder=installed[.synthesizer] {
                let manifest=try RVCSynthesisAssets.manifest(at:folder)
                voiceName=try RVCSynthesisAssets.voiceName(manifest)
                defaultIndexRate=try RVCSynthesisAssets.defaultRetrievalRate(manifest)
                if currentModelSHA != manifest.sha256 {
                    currentModelSHA=manifest.sha256;indexRate=defaultIndexRate
                }
                if let retrieval=installed[.retrieval] {
                    let profile=try RVCRetrievalAssets.descriptor(at:retrieval).profile
                    retrievalSupported=(try? RVCSynthesisAssets.validateRetrievalPair(manifest,usesRetrieval:true,retrievalProfile:profile)) != nil
                }
                if !retrievalSupported && indexRate != 0 {
                    indexRate=0
                    message="Retrieval disabled: install a matching verified pack to enable it."
                    state.append(message)
                }
            }
        }
        catch {installed=[:];retrievalSupported=false;currentModelSHA=nil;indexRate=0;message="Diagnostic storage could not be opened."}
    }
    var assetsReady:Bool {
        installed[.hubert] != nil && installed[.synthesizer] != nil &&
        (indexRate == 0 || installed[.retrieval] != nil)
    }
    var controlsValid:Bool {indexRate.isFinite && (0...1).contains(indexRate) && semitones.isFinite && (-24...24).contains(semitones)}
    func canConvert(audio:AudioStore)->Bool {
        state.mayStart(assets:assetsReady && controlsValid && (retrievalSupported || indexRate == 0),input:input != nil,foreground:active,
                       audioAvailable:!audio.processingInUse && !audio.microphoneInUse)
    }
    func setActive(_ value:Bool) {active=value;if !value {cancel(reason:"Stopping because the app entered the background.")}}
    func cancel(reason:String="Stop requested; waiting for the current operation to finish safely.") {
        guard state.busy else {return}
        state.requestCancel();message=reason;state.append(reason);work?.cancel()
    }
    func importerFailed() {if !state.busy {message="Nothing was imported."}}
    func install(_ role:RVCPreviewPack,from url:URL,audio:AudioStore) {
        performImport(.assetImport,audio:audio,label:"Verifying "+role.title.lowercased()+"…",
                      operation:{try RVCPreviewStore.install(role,from:url);return nil},apply:{_ in})
    }
    func importAudio(_ url:URL,audio:AudioStore) {
        let name=String(url.lastPathComponent.prefix(120))
        performImport(.audioImport,audio:audio,label:"Copying and checking audio…",
                      operation:{try RVCPreviewStore.importAudio(url)},apply:{result in
            guard let result else {return}
            self.input=result;self.inputName=name
        })
    }
    private func performImport(_ kind:RVCPreviewState.Kind,audio:AudioStore,label:String,
                               operation:@escaping @Sendable () throws -> URL?,
                               apply:@escaping (URL?)->Void) {
        guard !state.busy,active,let lease=audio.claimProcessing() else {return}
        guard let ticket=try? state.begin(kind) else {audio.releaseProcessing(lease);return}
        message=label;state.append(label)
        work=Task {
            var imported:URL?
            defer {audio.releaseProcessing(lease);work=nil;refresh()}
            do {
                let worker=Task.detached(priority:.userInitiated){try operation()}
                imported=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation()
                guard state.ticket==ticket else {return}
                apply(imported)
                state.finish(.succeeded,ticket:ticket)
                message=kind == .audioImport ? "Audio imported. Nothing has been uploaded." : "Diagnostic pack verified and installed."
                state.append(message)
            } catch {
                if kind == .audioImport,let imported {try? FileManager.default.removeItem(at:imported)}
                finishFailure(error,ticket:ticket)
            }
        }
    }
    func convert(audio:AudioStore) {
        guard canConvert(audio:audio),let source=input,
              let hubert=installed[.hubert],let synth=installed[.synthesizer],
              let lease=audio.claimProcessing() else {return}
        guard let ticket=try? state.begin(.conversion) else {audio.releaseProcessing(lease);return}
        // Capture settings once; every chunk of this job uses the same values.
        let rate=indexRate,shift=semitones,refine=refinePitch
        let retrieval=rate == 0 ? nil : installed[.retrieval]
        let name=inputName
        let destination=RVCPreviewStore.results.appendingPathComponent("RVC-preview-"+UUID().uuidString+".wav")
        audio.stop();message="Loading verified diagnostic models…";state.append(message)
        state.append("Voice model: "+voiceName)
        state.append("Pitch refinement: "+(refine ? "on" : "off"))
        state.append(String(format:"Retrieval %.1f%% · pitch %+.0f semitones",Double(rate)*100,shift))
        work=Task {
            defer {audio.releaseProcessing(lease);work=nil}
            do {
                let worker=Task.detached(priority:.userInitiated) {
                    let started=Date()
                    let inputIdentity=try RVCResultHistory.identity(source)
                    var hashes=["hubert":try RVCSynthesisAssets.manifest(at:hubert).sha256,
                                "synthesizer":try RVCSynthesisAssets.manifest(at:synth).sha256]
                    if let retrieval {
                        let pack=try RVCRetrievalAssets.descriptor(at:retrieval)
                        let canonical=pack.profile+"\n"+pack.files.sorted{$0.name<$1.name}.map{"\($0.name):\($0.bytes):\($0.sha256)"}.joined(separator:"\n")
                        hashes["retrieval"]=SHA256.hash(data:Data(canonical.utf8)).map{String(format:"%02x",$0)}.joined()
                    }
                    let converter=try await RVCNativeWindowConverter.open(hubertRoot:hubert,synthesizerRoot:synth,retrievalRoot:retrieval,cache:RVCPreviewStore.cache)
                    do {
                        let result=try await converter.convertMediaExperimentalAutocorrelation(input:source,output:destination,scratch:RVCPreviewStore.cache,seed:347,semitones:shift,indexRate:rate,refinePitch:refine,progress:{fraction in
                            Task {@MainActor in
                                guard self.state.ticket==ticket,self.state.phase == .working else {return}
                                let before=self.state.percent
                                self.state.progress(fraction,ticket:ticket)
                                if before != self.state.percent || fraction == 0 {
                                    self.message=fraction == 0 ? "Preprocessing audio · 0%" : (fraction >= 0.9 ? "Saving diagnostic preview · \(self.state.percent ?? 0)%" : "Converting diagnostic preview · \(self.state.percent ?? 0)%")
                                    self.state.append(self.message)
                                }
                            }
                        })
                        await converter.close()
                        do {
                            let after=try RVCResultHistory.identity(source)
                            guard after.bytes==inputIdentity.bytes,after.sha256==inputIdentity.sha256 else {throw RVCResultHistory.Failure.changed}
                            let context=RVCResultHistory.Context(inputName:name,inputSHA256:inputIdentity.sha256,inputBytes:inputIdentity.bytes,
                                modelSHA256:hashes,settings:.init(indexRate:rate,semitones:shift,refinePitch:refine),startedAt:started,completedAt:Date())
                            _ = try RVCResultHistory(root:RVCPreviewStore.results).publish(output:destination,context:context)
                        } catch {throw HistoryFailure.completedButUnindexed}
                        // Publication is irreversible, including cancellation after this point.
                        return result
                    } catch {await converter.close();throw error}
                }
                let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                refreshHistory()
                guard state.ticket==ticket else {return}
                if result.inputGain<1 {
                    state.append(String(format:"Input level reduced to %.3f%% to preserve filter peaks without clipping (peak %.6f).",Double(result.inputGain)*100,Double(result.inputPeak)))
                }
                state.finishCommitted(ticket:ticket)
                message="Diagnostic preview saved · 100%. Select it in saved previews to verify, listen or share."
                state.append(message)
            } catch {
                refreshHistory()
                if error is HistoryFailure {
                    state.finish(.failed,ticket:ticket)
                    message="The completed audio was kept, but its history receipt could not be saved. It is not available for playback here; do not repeat conversion to recover it."
                    state.append(message)
                } else {finishFailure(error,ticket:ticket)}
            }
        }
    }
    func refreshHistory() {
        historyRefresh?.cancel()
        historyRefresh=Task {
            do {
                let worker=Task.detached(priority:.utility) {
                    try FileManager.default.createDirectory(at:RVCPreviewStore.results,withIntermediateDirectories:true)
                    return try RVCResultHistory(root:RVCPreviewStore.results).list()
                }
                let listing=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation()
                history=listing.receipts
                historyNotice="Saved previews are diagnostic, not quality-verified. Select one to verify its audio before use."
                if listing.rejected>0 || listing.unindexed>0 {
                    historyNotice += " \(listing.rejected) invalid records and \(listing.unindexed) audio files without a receipt were kept but cannot be opened here."
                }
            } catch is CancellationError {} catch RVCResultHistory.Failure.bounds {
                history=[];historyNotice="History exceeds the safety limit of 200 records or 1,024 entries. Existing files were kept; no partial list is shown."
            } catch {
                history=[];historyNotice="Saved preview history could not be read safely. Existing files were kept."
            }
        }
    }
    func selectHistory(_ receipt:RVCResultHistory.Receipt,audio:AudioStore) {
        guard !state.busy,active,let lease=audio.claimProcessing() else {return}
        guard let ticket=try? state.begin(.historyLoad) else {audio.releaseProcessing(lease);return}
        audio.stop();message="Verifying saved audio and preparing a private playback copy…"
        work=Task {
            var snapshot:URL?
            defer {audio.releaseProcessing(lease);work=nil}
            do {
                let worker=Task.detached(priority:.userInitiated) {
                    try FileManager.default.createDirectory(at:RVCPreviewStore.cache,withIntermediateDirectories:true)
                    return try RVCResultHistory(root:RVCPreviewStore.results).snapshot(receipt,cache:RVCPreviewStore.cache)
                }
                snapshot=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation()
                guard state.ticket==ticket else {throw CancellationError()}
                // Only this owned verified copy is passed to AudioActions, never a history URL.
                output=snapshot;outputName=receipt.context.inputName
                state.finish(.succeeded,ticket:ticket);message="Saved diagnostic audio verified. Ready to listen or share."
            } catch {
                // Returned copies may be reused by an earlier share sheet. Never delete them.
                finishFailure(error,ticket:ticket)
                if case RVCResultHistory.Failure.bounds = error {
                    message="Playback copy storage reached its safety limit (200 copies, 1.6 GB, or low free space). Saved results were kept."
                    state.append(message)
                }
            }
        }
    }
    private func finishFailure(_ error:Error,ticket:UUID) {
        guard state.ticket==ticket else {return}
        if error is CancellationError || state.phase == .cancelling {
            state.finish(.cancelled,ticket:ticket);message=state.kind == .assetImport ? "Stopped. Any pack fully verified before cancellation was kept." : "Stopped. Partial output was removed; earlier results were kept."
        } else {
            state.finish(.failed,ticket:ticket)
            if let retrievalError=error as? RVCNativeRetrieval.Failure {
                switch retrievalError {
                case .missingNeighbors:
                    message="The diagnostic voice index has too few matches for this audio. Conversion stopped; no completed result was saved."
                case .shape, .value:
                    message="The diagnostic retrieval assets could not process this audio. Check the installed retrieval pack."
                }
            } else if error is RVCSynthesisFailure {
                message="The diagnostic models could not run. Check the installed packs and available memory."
            } else if error is RVCFileError {
                message="The audio could not be processed. Check its format, duration and available storage."
            } else {message="This operation failed. Check the selected files and available storage."}
            let failure=error as NSError
            state.append("Failure: "+failure.domain+" (\(failure.code)).")
        }
        state.append(message)
    }
}
#endif
