import Foundation
import Testing
@testable import CatchKit

@MainActor
@Suite
struct SessionStoreTests {
    @Test
    func archivedListedSessionDisappearsFromVisibleSessions() {
        let store = SessionStore(appSupportDirectoryName: "CatchTests-\(UUID().uuidString)")
        let active = session(id: "session-1", title: "Active")

        store.mergeListedSessions([active])
        #expect(store.sessions.map(\.id) == [active.id])

        store.mergeListedSessions([
            session(id: "session-1", title: "Active", isArchived: true)
        ])
        #expect(store.sessions.isEmpty)

        store.mergeListedSessions([active])
        #expect(store.sessions.map(\.id) == [active.id])
    }

    @Test
    func omittedListedSessionDisappearsFromVisibleSessions() {
        let store = SessionStore(appSupportDirectoryName: "CatchTests-\(UUID().uuidString)")
        let first = session(id: "session-1", title: "First", updatedAt: Date(timeIntervalSinceReferenceDate: 10))
        let second = session(id: "session-2", title: "Second", updatedAt: Date(timeIntervalSinceReferenceDate: 20))

        store.mergeListedSessions([first, second])
        #expect(store.sessions.map(\.id) == [second.id, first.id])

        store.mergeListedSessions([second])
        #expect(store.sessions.map(\.id) == [second.id])
    }

    private func session(
        id: String,
        title: String,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0),
        isArchived: Bool = false
    ) -> CodexSession {
        CodexSession(
            provider: .goose,
            sessionID: id,
            cwd: "/tmp",
            title: title,
            updatedAt: updatedAt,
            status: .idle,
            lastEvent: "",
            isArchived: isArchived
        )
    }
}
