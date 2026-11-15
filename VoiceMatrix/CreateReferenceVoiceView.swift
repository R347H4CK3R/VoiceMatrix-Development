import SwiftUI
import UniformTypeIdentifiers

struct CreateReferenceVoiceView: View {
    @EnvironmentObject private var library: CharacterLibrary
    @EnvironmentObject private var audio: AudioStore
    @EnvironmentObject private var studio: SpeechStudio
    @StateObject private var recorder=Recorder()
    @State private var name=""
    @State private var transcript=""
    @State private var permitted=false
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
                Text("\(transcript.count)/2,000 characters").font(.caption)
                Toggle("I have permission to use this voice recording",isOn:$permitted).disabled(blocked)
            }
            Section("3 · Save to Voices") {
                Button("Save and select voice") {
                    if let source=recorder.output {
                        library.createReferenceVoice(from:source,name:name,transcript:transcript,
                            permissionConfirmed:permitted,audio:audio,studio:studio)
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(blocked || recorder.recording || recorder.output == nil || !permitted ||
                        name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count>80 ||
                        transcript.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || transcript.count>2000)
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
        .onDisappear {recorder.discard();audio.stop()}
    }
}
