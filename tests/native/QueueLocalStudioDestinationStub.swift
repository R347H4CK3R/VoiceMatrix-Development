// Test-only destination for the isolated queue-boundary typecheck.
// This does not validate Video Voice Studio. The full native-app gate compiles
// the real VoiceMatrix/LocalVideoStudioView.swift with its production dependencies.
#if QUEUE_BOUNDARY_TYPECHECK
import SwiftUI
struct LocalVideoStudioView: View {
    init(initialSourceURL: String? = nil) {}
    var body: some View { EmptyView() }
}
#endif
