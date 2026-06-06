import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ComposerView(prompt: $store.prompt, isFocused: $promptFocused) {
                Task { await store.submitPrompt() }
            }

            Divider()

            SessionListView(sessions: store.sessions, selectedSessionID: $store.selectedSessionID)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .padding(1)
        .onReceive(NotificationCenter.default.publisher(for: .focusPromptField)) { _ in
            promptFocused = true
        }
        .onAppear {
            promptFocused = true
        }
        .background {
            KeyboardMonitor { direction in
                store.moveSelection(direction: direction)
            }
        }
    }
}
