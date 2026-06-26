import Foundation
import Testing
@testable import CatchKit

@Suite
struct SessionDeepLinkTests {
    @Test
    func buildsGooseInternalSessionURL() {
        let session = Session(
            provider: .goose,
            sessionID: "abc-123",
            cwd: "",
            title: "Session",
            updatedAt: nil,
            status: .idle,
            lastEvent: ""
        )

        #expect(session.gooseInternalSessionURL?.absoluteString == "goose-internal://session/abc-123")
    }

    @Test
    func encodesSessionIDAsSinglePathSegment() {
        let session = Session(
            provider: .goose,
            sessionID: "id/with spaces",
            cwd: "",
            title: "Session",
            updatedAt: nil,
            status: .idle,
            lastEvent: ""
        )

        #expect(session.gooseInternalSessionURL?.absoluteString == "goose-internal://session/id%2Fwith%20spaces")
    }

    @Test
    func ignoresBlankSessionID() {
        let session = Session(
            provider: .goose,
            sessionID: "  ",
            cwd: "",
            title: "Session",
            updatedAt: nil,
            status: .idle,
            lastEvent: ""
        )

        #expect(session.gooseInternalSessionURL == nil)
    }
}
