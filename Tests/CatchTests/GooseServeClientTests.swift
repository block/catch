import Testing
@testable import CatchKit

@Suite
struct GooseServeClientTests {
    @Test
    func embeddedConfigurationRequiresTokenizedServerURL() {
        #expect(throws: GooseServeClientError.embeddedServerTokenMissing) {
            _ = try GooseServeClient.EmbeddedServerConfiguration(environment: [
                "GOOSE_SERVE_URL": "ws://127.0.0.1:12345/acp"
            ])
        }
    }

    @Test
    func embeddedConfigurationRejectsEmptyToken() {
        #expect(throws: GooseServeClientError.embeddedServerTokenMissing) {
            _ = try GooseServeClient.EmbeddedServerConfiguration(environment: [
                "GOOSE_SERVE_URL": "ws://127.0.0.1:12345/acp?token="
            ])
        }
    }

    @Test
    func embeddedConfigurationPreservesExistingToken() throws {
        let configuration = try GooseServeClient.EmbeddedServerConfiguration(environment: [
            "GOOSE_SERVE_URL": "ws://127.0.0.1:12345/acp?token=existing"
        ])

        #expect(configuration.webSocketURL.absoluteString == "ws://127.0.0.1:12345/acp?token=existing")
    }

    @Test
    func embeddedConfigurationRequiresServerURL() {
        #expect(throws: GooseServeClientError.embeddedServerURLMissing) {
            _ = try GooseServeClient.EmbeddedServerConfiguration(environment: [:])
        }
    }

    @Test
    func embeddedConfigurationRejectsNonWebSocketURL() {
        #expect(throws: GooseServeClientError.invalidEmbeddedServerURL("http://127.0.0.1:12345/acp?token=secret")) {
            _ = try GooseServeClient.EmbeddedServerConfiguration(environment: [
                "GOOSE_SERVE_URL": "http://127.0.0.1:12345/acp?token=secret"
            ])
        }
    }
}
