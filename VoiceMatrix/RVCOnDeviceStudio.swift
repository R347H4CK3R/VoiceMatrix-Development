#if os(iOS)
import Foundation
import Combine

@MainActor final class RVCOnDeviceStudio:ObservableObject {
    @Published var indexRate:Float=0.75
    @Published var semitones:Double=0
    @Published private(set) var state=RVCPreviewState()
    @Published private(set) var installed:[RVCPreviewPack:URL]=[:]
    @Published private(set) var input:URL?
    @Published private(set) var inputName=""
    @Published private(set) var output:URL?
    @Published private(set) var outputName=""
    @Published private(set) var message="Install the encoder and diagnostic voice model, then import audio. Retrieval data is optional when its strength is zero."
    private var work:Task<Void,Never>?
    private var active=true
    init() {refresh()}
    func refresh() {
        do {try RVCPreviewStore.prepare();installed=try RVCPreviewStore.locations()}
        catch {installed=[:];message="Diagnostic storage could not be opened."}
    }
    var assetsReady:Bool {
        installed[.hubert] != nil && installed[.synthesizer] != nil &&
        (indexRate == 0 || installed[.retrieval] != nil)
    }
    var controlsValid:Bool {indexRate.isFinite && (0...1).contains(indexRate) && semitones.isFinite && (-24...24).contains(semitones)}
    func canConvert(audio:AudioStore)->Bool {
        state.mayStart(assets:assetsReady && controlsValid,input:input != nil,foreground:active,
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
            let previous=self.input;self.input=result;self.inputName=name
            if let previous {try? FileManager.default.removeItem(at:previous)}
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
        let rate=indexRate,shift=semitones
        let retrieval=rate == 0 ? nil : installed[.retrieval]
        let name=inputName
        let destination=RVCPreviewStore.results.appendingPathComponent("RVC-preview-"+UUID().uuidString+".wav")
        audio.stop();message="Loading verified diagnostic models…";state.append(message)
        state.append(String(format:"Retrieval %.1f%% · pitch %+.0f semitones",Double(rate)*100,shift))
        work=Task {
            defer {audio.releaseProcessing(lease);work=nil}
            var committed=false
            do {
                let worker=Task.detached(priority:.userInitiated) {
                    let converter=try await RVCNativeWindowConverter.open(hubertRoot:hubert,synthesizerRoot:synth,retrievalRoot:retrieval,cache:RVCPreviewStore.cache)
                    do {
                        let result=try await converter.convertMediaExperimentalAutocorrelation(input:source,output:destination,scratch:RVCPreviewStore.cache,seed:347,semitones:shift,indexRate:rate,progress:{fraction in
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
                        return result
                    } catch {await converter.close();throw error}
                }
                let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                committed=true
                try Task.checkCancellation()
                guard state.ticket==ticket else {try? FileManager.default.removeItem(at:destination);return}
                if result.inputGain<1 {
                    state.append(String(format:"Input level reduced to %.3f%% to preserve filter peaks without clipping (peak %.6f).",Double(result.inputGain)*100,Double(result.inputPeak)))
                }
                output=destination;outputName=name
                state.finish(.succeeded,ticket:ticket)
                message="Diagnostic preview complete · 100%. Listen and review the result."
                state.append(message)
            } catch {
                if committed {try? FileManager.default.removeItem(at:destination)}
                finishFailure(error,ticket:ticket)
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
