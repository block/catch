import Foundation

extension CodexSession {
    static var previewSessions: [CodexSession] {
        [
            CodexSession(
                provider: .goose,
                sessionID: "preview-goose-1",
                cwd: "~/Development/catch",
                title: "Square iOS Dependency Graph R...",
                updatedAt: Date().addingTimeInterval(-240),
                status: .working,
                lastEvent: "Working"
            ),
            CodexSession(
                provider: .goose,
                sessionID: "preview-goose-2",
                cwd: "~/Development/catch",
                title: "At symbol",
                updatedAt: Date().addingTimeInterval(-960),
                status: .idle,
                lastEvent: "Idle"
            ),
            CodexSession(
                provider: .goose,
                sessionID: "preview-goose-4",
                cwd: "~/Development/catch",
                title: "Model selector polish",
                updatedAt: Date().addingTimeInterval(-2100),
                status: .idle,
                lastEvent: "Idle"
            ),
            CodexSession(
                provider: .goose,
                sessionID: "preview-goose-5",
                cwd: "~/Development/catch",
                title: "Today's date",
                updatedAt: Date().addingTimeInterval(-3600),
                status: .idle,
                lastEvent: "Idle"
            ),
            CodexSession(
                provider: .goose,
                sessionID: "preview-goose-3",
                cwd: "~/Development/catch",
                title: "Before and after",
                updatedAt: Date().addingTimeInterval(-7200),
                status: .idle,
                lastEvent: "Idle"
            ),
            CodexSession(
                provider: .goose,
                sessionID: "preview-goose-6",
                cwd: "~/Development/catch",
                title: "Prompt focus regression",
                updatedAt: Date().addingTimeInterval(-12600),
                status: .idle,
                lastEvent: "Idle"
            )
        ]
    }
}
