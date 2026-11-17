import SwiftUI
import UniformTypeIdentifiers

/// Permission is for one selected local clip, not every later recording/import.
struct ReferenceVoiceConsent {
    private(set) var approvedSource: URL?
    func permits(_ source: URL?) -> Bool {
        guard let source else { return false }
        return approvedSource == source
    }
    mutating func setPermission(_ permitted: Bool, for source: URL?) {
        approvedSource = permitted ? source : nil
    }
    mutating func sourceChanged(from old: URL?, to new: URL?) {
        if old != new { approvedSource = nil }
    }
}

struct CreateReferenceVoiceView: View {
    @EnvironmentObject private var library: CharacterLibrary
    @EnvironmentObject private var audio: AudioStore
    @EnvironmentObject private var studio: SpeechStudio
    @StateObject private var recorder=Recorder()
    @State private var name=""
    @State private var transcript=""
    @State private var consent=ReferenceVoiceConsent()
    @State private var importing=false
    private var blocked:Bool {library.busy || audio.processingInUse || recorder.requestingPermission}
    var body:some View {
        Form {
            Section("1 · Record or choose a short clip") {
                Text("Use one clear voice, with no music or other speakers. Record or import 0.5–10 seconds.")
                HStack {
                    Button(recorder.recording ? "Stop recording" : "Record") {
                        if recorder.recording {recorder.stop()}
                        else {Task {await recorder.start(audio:audio)}}
                    }.disabled(blocked || (!recorder.recording && audio.microphoneInUse))
                    Button("Choose audio") {importing=true}
                        .disabled(blocked || recorder.recording || audio.microphoneInUse)
                }
                Text(recorder.status).font(.caption)
                if let source=recorder.output, !recorder.recording {
                    Button("Listen to reference") {audio.play(source)}.disabled(blocked)
                }
            }
            Section("2 · Name and spoken words") {
                TextField("Voice name",text:$name).disabled(blocked)
                Text("Type exactly what is spoken in the clip. These words condition the speech engine; they are not new text to generate.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text:$transcript).frame(minHeight:100)
                    .accessibilityLabel("Exact words in reference recording").disabled(blocked)
                Text("\(transcript.count) characters").font(.caption)
                if transcript.utf8.count > F5SpeechChunks.maximumReferenceBytes {
                    Text("This transcript is too long for the speech engine. Use a shorter clip and its exact words.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("I have permission to use this voice recording",isOn:Binding(
                    get:{consent.permits(recorder.output)},
                    set:{consent.setPermission($0,for:recorder.output)}))
                    .disabled(blocked || recorder.recording || recorder.output == nil)
            }
            Section("3 · Save to Voices") {
                Button("Save and select voice") {
                    if let source=recorder.output, consent.permits(source) {
                        library.createReferenceVoice(from:source,name:name,transcript:transcript,
                            permissionConfirmed:consent.permits(source),audio:audio,studio:studio)
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(blocked || recorder.recording || recorder.output == nil || !consent.permits(recorder.output) ||
                        name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count>80 ||
                        transcript.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || transcript.utf8.count>F5SpeechChunks.maximumReferenceBytes)
                    .accessibilityIdentifier("save-reference-voice")
                if library.busy {
                    ProgressView()
                    Button("Cancel",role:.cancel) {library.cancel()}
                }
                Text(library.message).font(.callout).accessibilityAddTraits(.updatesFrequently)
                Text("Saves a reference profile on this iPhone. No diagnostic pack, laptop or model training is required. Voice resemblance must be judged by listening.")
                    .font(.caption).foregroundStyle(.secondary)
                if !library.engineAvailable {
                    Text("This build lacks the shared speech engine. You can save the reference now, but generating speech requires a build containing that engine.").font(.caption)
                }
            }
        }
        .navigationTitle("Create a voice")
        .fileImporter(isPresented:$importing,allowedContentTypes:[.audio]) {result in
            switch result {
            case .success(let url):recorder.importAudio(url)
            case .failure:recorder.status="Audio could not be opened. Try again."
            }
        }
        .onChange(of:recorder.output) {old,new in consent.sourceChanged(from:old,to:new)}
        .onDisappear {recorder.discard();audio.stop()}
    }
}
