#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct RVCOnDeviceView:View {
    @EnvironmentObject private var preview:RVCOnDeviceStudio
    @EnvironmentObject private var audio:AudioStore
    @State private var importing=false
    @State private var selectedPack:RVCPreviewPack?
    private var unavailable:Bool {preview.state.busy || audio.processingInUse || audio.microphoneInUse}
    var body:some View {
        Form {
            Section {
                Label("Diagnostic preview",systemImage:"testtube.2").font(.headline)
                Text("This uses a diagnostic model, not one of your character voices. Pitch can be inaccurate on human speech. Phone performance and voice quality still need validation.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Your existing voices stay in the Voices tab.").font(.caption).foregroundStyle(.secondary)
            }
            Section("1 · Install offline assets") {
                ForEach(RVCPreviewPack.allCases) {role in
                    Button {
                        selectedPack=role;importing=true
                    } label: {
                        HStack {
                            Label(role.title,systemImage:preview.installed[role] == nil ? "folder.badge.plus" : "checkmark.circle")
                            Spacer()
                            Text(preview.installed[role] == nil ? "Choose folder" : "Installed").font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(unavailable).accessibilityIdentifier("rvc-preview-pack-"+role.rawValue)
                }
                Text("Choose the supported pack folders from Files. Files are verified and copied privately onto this iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("2 · Import your audio") {
                Button {
                    selectedPack=nil;importing=true
                } label: {Label(preview.inputName.isEmpty ? "Choose audio" : preview.inputName,systemImage:"waveform")}
                    .disabled(unavailable).accessibilityIdentifier("rvc-preview-import-audio")
                Text("Short clips are best for evaluating the preview. Longer files need additional storage and processing time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("3 · Create a diagnostic preview") {
                Button {preview.convert(audio:audio)} label: {
                    Label("Run diagnostic preview",systemImage:"play.fill").frame(maxWidth:.infinity)
                }.buttonStyle(.borderedProminent)
                    .disabled(!preview.canConvert(audio:audio)).accessibilityIdentifier("rvc-preview-run")
                if preview.state.busy {
                    if let percent=preview.state.percent {
                        ProgressView(value:Double(percent),total:100)
                        Text("\(percent)%").monospacedDigit().accessibilityIdentifier("rvc-preview-percent")
                    } else {ProgressView("Checking selected files…")}
                    Button("Cancel",role:.cancel){preview.cancel()}
                        .disabled(preview.state.phase == .cancelling).accessibilityIdentifier("rvc-preview-cancel")
                }
                Text(preview.message).font(.callout).accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("rvc-preview-status")
                if preview.installed.count<3 {Text("Install all three packs to enable conversion.").font(.caption).foregroundStyle(.secondary)}
                else if preview.input == nil {Text("Import audio to enable conversion.").font(.caption).foregroundStyle(.secondary)}
            }
            Section("4 · Listen, save or share") {
                if let output=preview.output {
                    Text("Diagnostic preview of "+preview.outputName).font(.caption)
                    AudioActions(url:output)
                } else {Text("A completed result will appear here.").foregroundStyle(.secondary)}
            }
            Section("Live log") {
                if preview.state.events.isEmpty {Text("No work started yet.").foregroundStyle(.secondary)}
                ForEach(preview.state.events) {entry in
                    VStack(alignment:.leading,spacing:3) {
                        Text(entry.message).font(.caption)
                        Text(entry.date,style:.time).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("On-device RVC")
        .accessibilityIdentifier("rvc-preview-screen")
        .fileImporter(isPresented:$importing,allowedContentTypes:selectedPack == nil ? [.audio] : [.folder]) {result in
            switch result {
            case .success(let url):
                if let selectedPack {preview.install(selectedPack,from:url,audio:audio)}
                else {preview.importAudio(url,audio:audio)}
            case .failure:preview.importerFailed()
            }
        }
        .onAppear {preview.refresh()}
    }
}
#endif
