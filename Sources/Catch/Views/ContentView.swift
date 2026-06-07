import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @FocusState private var promptFocused: Bool
    let isTestBuild: Bool
    let keyboardMonitorEnabled: Bool

    init(isTestBuild: Bool = false, keyboardMonitorEnabled: Bool = true) {
        self.isTestBuild = isTestBuild
        self.keyboardMonitorEnabled = keyboardMonitorEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            if isTestBuild {
                Text("TEST BUILD")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.orange)
            }

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
            if keyboardMonitorEnabled {
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
}
