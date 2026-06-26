import Testing
@testable import CatchKit

@Suite
struct GooseServeClientTests {
    @Test
    func newSessionParamsIncludeProjectMetadataWhenProjectIsSelected() {
        let configuration = GooseSessionConfiguration(
            providerID: "databricks_v2",
            modelID: "openai/gpt-5",
            cwd: "/Users/test/project",
            projectID: "sample-project",
            reasoningEffort: "medium",
            invokedAgent: nil
        )

        let params = GooseServeClient.newSessionParams(configuration: configuration).rawValue

        #expect(params["cwd"] as? String == "/Users/test/project")
        #expect((params["mcpServers"] as? [Any])?.isEmpty == true)
        #expect(params["_meta"] as? [String: String] == [
            "provider": "databricks_v2",
            "projectId": "sample-project"
        ])
    }

    @Test
    func newSessionParamsOmitMetadataWithoutProjectProviderOrPersona() {
        let configuration = GooseSessionConfiguration(
            providerID: nil,
            modelID: nil,
            cwd: "/Users/test",
            projectID: nil,
            reasoningEffort: nil,
            invokedAgent: nil
        )

        #expect(GooseServeClient.newSessionParams(configuration: configuration).rawValue["_meta"] == nil)
    }

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
