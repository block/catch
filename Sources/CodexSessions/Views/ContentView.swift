import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ComposerView(
                prompt: $store.prompt,
                isFocused: $promptFocused,
                onMove: { direction in
                    store.moveSelection(direction: direction)
                },
                onSubmit: {
                    Task { await store.submitPrompt() }
                }
            )

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
        .onChange(of: promptFocused) { _, isFocused in
            guard !isFocused else { return }

            DispatchQueue.main.async {
                promptFocused = true
            }
        }
        .onAppear {
            promptFocused = true
        }
        .background {
            KeyboardMonitor(
                onMove: { direction in
                    store.moveSelection(direction: direction)
                },
                onEscape: {
                    NSApp.hide(nil)
                }
            )
        }
    }
}
