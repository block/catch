import Testing
@testable import CatchKit

@Suite
struct SessionTitleResolverTests {
    @Test
    func placeholderTitleKeepsProvisionalPromptTitle() {
        #expect(SessionTitleResolver.title(listedTitle: "New chat", provisionalTitle: "Summarize the logs") == "Summarize the logs")
        #expect(SessionTitleResolver.title(listedTitle: "  new chat  ", provisionalTitle: "Summarize the logs") == "Summarize the logs")
        #expect(SessionTitleResolver.title(listedTitle: "", provisionalTitle: "Summarize the logs") == "Summarize the logs")
    }

    @Test
    func generatedTitleReplacesProvisionalPromptTitle() {
        #expect(SessionTitleResolver.title(listedTitle: "Log summary", provisionalTitle: "Summarize the logs") == "Log summary")
    }

    @Test
    func provisionalTitleSurvivesPlaceholderUntilGeneratedTitleArrives() {
        var titles = ProvisionalSessionTitles()
        let session = CodexSession(
            provider: .goose,
            sessionID: "session-1",
            cwd: "/tmp",
            title: "New chat",
            updatedAt: nil,
            status: .idle,
            lastEvent: ""
        )

        titles.record("Verbatim submitted prompt", for: session.id)

        #expect(titles.resolvedTitle(for: session) == "Verbatim submitted prompt")

        let generatedSession = CodexSession(
            provider: .goose,
            sessionID: "session-1",
            cwd: "/tmp",
            title: "Generated session title",
            updatedAt: nil,
            status: .idle,
            lastEvent: ""
        )

        #expect(titles.resolvedTitle(for: generatedSession) == "Generated session title")
        #expect(titles.resolvedTitle(for: session) == "New chat")
    }
}
