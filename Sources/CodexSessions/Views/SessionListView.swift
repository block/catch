import SwiftUI

struct SessionListView: View {
    let sessions: [CodexSession]
    @Binding var selectedSessionID: String?
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var viewportFrame: CGRect = .zero

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            isSelected: session.id == selectedSessionID
                        )
                        .id(session.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSessionID = session.id
                            NotificationCenter.default.post(name: .focusPromptField, object: nil)
                        }
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: RowFramePreferenceKey.self,
                                    value: [session.id: geometry.frame(in: .named("sessionList"))]
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ViewportFramePreferenceKey.self,
                        value: geometry.frame(in: .named("sessionList"))
                    )
                }
            }
            .coordinateSpace(name: "sessionList")
            .onPreferenceChange(RowFramePreferenceKey.self) { frames in
                rowFrames = frames
                scrollSelectionIntoView(proxy: proxy)
            }
            .onPreferenceChange(ViewportFramePreferenceKey.self) { frame in
                viewportFrame = frame
                scrollSelectionIntoView(proxy: proxy)
            }
            .onChange(of: selectedSessionID) { _, _ in
                scrollSelectionIntoView(proxy: proxy)
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "text.bubble", description: Text("Create a session from the prompt field."))
                    .padding()
            }
        }
    }

    private func scrollSelectionIntoView(proxy: ScrollViewProxy) {
        guard
            let selectedSessionID,
            let rowFrame = rowFrames[selectedSessionID],
            viewportFrame != .zero
        else {
            return
        }

        if rowFrame.minY < viewportFrame.minY {
            proxy.scrollTo(selectedSessionID, anchor: .top)
        } else if rowFrame.maxY > viewportFrame.maxY {
            proxy.scrollTo(selectedSessionID, anchor: .bottom)
        }
    }
}

struct SessionRowView: View {
    let session: CodexSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(session.provider.badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 10)

            if session.status == .working {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Text(AppFormatters.compactAge(for: session.updatedAt))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
            }
        }
    }
}

private struct RowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ViewportFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
