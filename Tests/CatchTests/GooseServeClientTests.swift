import Testing
@testable import CatchKit

@Suite
struct GooseServeClientTests {
    @Test
    func embeddedConfigurationAppendsSecretToken() throws {
        let configuration = try GooseServeClient.EmbeddedServerConfiguration(environment: [
            "GOOSE_SERVE_URL": "ws://127.0.0.1:12345/acp",
            "GOOSE_SERVER__SECRET_KEY": "secret"
        ])

        #expect(configuration.webSocketURL.absoluteString == "ws://127.0.0.1:12345/acp?token=secret")
    }

    @Test
    func embeddedConfigurationPreservesExistingToken() throws {
        let configuration = try GooseServeClient.EmbeddedServerConfiguration(environment: [
            "GOOSE_SERVE_URL": "ws://127.0.0.1:12345/acp?token=existing",
            "GOOSE_SERVER__SECRET_KEY": "ignored"
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
    func embeddedConfigurationRequiresSecretWhenURLHasNoToken() {
        #expect(throws: GooseServeClientError.embeddedServerSecretMissing) {
            _ = try GooseServeClient.EmbeddedServerConfiguration(environment: [
                "GOOSE_SERVE_URL": "ws://127.0.0.1:12345/acp"
            ])
        }
    }

    @Test
    func embeddedConfigurationRejectsNonWebSocketURL() {
        #expect(throws: GooseServeClientError.invalidEmbeddedServerURL("http://127.0.0.1:12345/acp")) {
            _ = try GooseServeClient.EmbeddedServerConfiguration(environment: [
                "GOOSE_SERVE_URL": "http://127.0.0.1:12345/acp",
                "GOOSE_SERVER__SECRET_KEY": "secret"
            ])
        }
    }
}
