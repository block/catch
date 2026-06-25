import AppKit
import SwiftUI

struct ContentView: View {
    let isTestBuild: Bool
    let testBuildLabel: String
    let keyboardMonitorEnabled: Bool

    init(isTestBuild: Bool = false, testBuildLabel: String = "TEST BUILD", keyboardMonitorEnabled: Bool = true) {
        self.isTestBuild = isTestBuild
        self.testBuildLabel = testBuildLabel
        self.keyboardMonitorEnabled = keyboardMonitorEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            if isTestBuild {
                Text(testBuildLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
            }

            SessionCreationConceptView(keyboardMonitorEnabled: keyboardMonitorEnabled)
        }
    }
}

#Preview("Content") {
    ContentPreviewHost(isTestBuild: false)
}

#Preview("Content Test Build") {
    ContentPreviewHost(isTestBuild: true, testBuildLabel: "TEST BUILD")
}

#Preview("Content Named Test Build") {
    ContentPreviewHost(isTestBuild: true, testBuildLabel: "COMMAND PALETTE")
}

private struct ContentPreviewHost: View {
    @StateObject private var store = SessionStore(appSupportDirectoryName: "CatchPreview")
    let isTestBuild: Bool
    var testBuildLabel = "TEST BUILD"

    var body: some View {
        ContentView(isTestBuild: isTestBuild, testBuildLabel: testBuildLabel, keyboardMonitorEnabled: false)
            .environmentObject(store)
            .frame(width: sessionCreationConceptWidth, height: sessionCreationConceptHeight)
            .onAppear {
                store.isConnected = true
                store.sessions = CodexSession.previewSessions
            }
    }
}
