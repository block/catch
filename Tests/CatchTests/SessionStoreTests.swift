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

    @Test
    func listedSessionsSortByLastMessageActivityBeforeUpdatedAt() {
        let store = SessionStore(appSupportDirectoryName: "CatchTests-\(UUID().uuidString)")
        let statusOnlyNewer = session(
            id: "status-only-newer",
            title: "Status-only newer",
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            lastMessageAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let messageActiveOlder = session(
            id: "message-active-older",
            title: "Message-active older",
            updatedAt: Date(timeIntervalSinceReferenceDate: 20),
            lastMessageAt: Date(timeIntervalSinceReferenceDate: 90)
        )

        store.mergeListedSessions([statusOnlyNewer, messageActiveOlder])

        #expect(store.sessions.map(\.id) == [messageActiveOlder.id, statusOnlyNewer.id])
        #expect(store.sessions.map(\.activityAt) == [
            messageActiveOlder.lastMessageAt,
            statusOnlyNewer.lastMessageAt
        ])
    }

    @Test
    func listedSessionsFallbackToUpdatedAtWhenLastMessageIsMissing() {
        let store = SessionStore(appSupportDirectoryName: "CatchTests-\(UUID().uuidString)")
        let older = session(id: "older", title: "Older", updatedAt: Date(timeIntervalSinceReferenceDate: 10))
        let newer = session(id: "newer", title: "Newer", updatedAt: Date(timeIntervalSinceReferenceDate: 20))

        store.mergeListedSessions([older, newer])

        #expect(store.sessions.map(\.id) == [newer.id, older.id])
        #expect(store.sessions.map(\.activityAt) == [newer.updatedAt, older.updatedAt])
    }

    private func session(
        id: String,
        title: String,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0),
        lastMessageAt: Date? = nil,
        isArchived: Bool = false
    ) -> Session {
        Session(
            provider: .goose,
            sessionID: id,
            cwd: "/tmp",
            title: title,
            updatedAt: updatedAt,
            lastMessageAt: lastMessageAt,
            status: .idle,
            lastEvent: "",
            isArchived: isArchived
        )
    }
}
