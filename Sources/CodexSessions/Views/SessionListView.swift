import SwiftUI

struct SessionListView: View {
    let sessions: [CodexSession]
    @Binding var selectedSessionID: String?

    var body: some View {
        List(selection: $selectedSessionID) {
            ForEach(sessions) { session in
                SessionRowView(session: session)
                    .tag(session.id)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "text.bubble", description: Text("Create a session from the prompt field."))
                    .padding()
            }
        }
    }
}

struct SessionRowView: View {
    let session: CodexSession

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
        .padding(.vertical, 8)
    }
}
