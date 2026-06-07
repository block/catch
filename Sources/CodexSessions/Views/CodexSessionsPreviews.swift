import SwiftUI

#Preview("Content") {
    ContentPreviewHost(isTestBuild: false)
}

#Preview("Content Test Build") {
    ContentPreviewHost(isTestBuild: true)
}

#Preview("Session List Empty") {
    @Previewable @State var selectedSessionID: String?

    SessionListView(sessions: [], selectedSessionID: $selectedSessionID)
        .frame(width: 560, height: 300)
}

#Preview("Composer") {
    ComposerPreviewHost()
}

private struct ContentPreviewHost: View {
    @StateObject private var store = SessionStore(appSupportDirectoryName: "CodexSessionsPreview")
    let isTestBuild: Bool

    var body: some View {
        ContentView(isTestBuild: isTestBuild, keyboardMonitorEnabled: false)
            .environmentObject(store)
            .frame(width: 560, height: 430)
    }
}

private struct ComposerPreviewHost: View {
    @State private var prompt = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ComposerView(
            prompt: $prompt,
            isFocused: $isFocused,
            onMove: { _ in },
            onSubmit: {}
        )
        .frame(width: 560)
        .onAppear {
            isFocused = true
        }
    }
}
