import Testing
@testable import CatchKit

@Suite
struct GooseAgentInvocationTests {
    @Test
    func `new session params include Goose persona metadata`() {
        let configuration = GooseSessionConfiguration(
            providerID: "databricks_v2",
            modelID: "goose-gpt-5-5",
            cwd: "/tmp/project",
            projectID: "project-1",
            reasoningEffort: "high",
            invokedAgent: GooseInvokedAgent(
                personaID: "/Users/test/.agents/agents/block.md",
                displayName: "block.md",
                systemPrompt: "Use Block guidance."
            )
        )

        let params = GooseServeClient.newSessionParams(configuration: configuration).rawValue

        #expect(params["cwd"] as? String == "/tmp/project")
        #expect((params["mcpServers"] as? [Any])?.isEmpty == true)
        #expect(params["_meta"] as? [String: String] == [
            "provider": "databricks_v2",
            "projectId": "project-1",
            "personaId": "/Users/test/.agents/agents/block.md"
        ])
    }

    @Test
    func `append system prompt params match Goose extension shape`() {
        let params = GooseServeClient.appendSystemPromptParams(
            sessionID: "session-1",
            key: "client_system_prompt",
            text: "Use Block guidance."
        ).rawValue

        #expect(params["sessionId"] as? String == "session-1")
        #expect(params["mode"] as? String == "append")
        #expect(params["key"] as? String == "client_system_prompt")
        #expect(params["text"] as? String == "Use Block guidance.")
    }

    @Test
    func `skill assistant prompt matches Goose2 selected skill format`() {
        let prompt = GooseServeClient.skillAssistantPrompt(
            skills: [
                GooseInvokedSkill(id: "global:/Users/test/.agents/skills/ai-app-info", displayName: "ai-app-info"),
                GooseInvokedSkill(id: "builtin:goose-help", displayName: "goose-help")
            ]
        )

        #expect(prompt == "Use these skills for this request: ai-app-info, goose-help.")
    }

    @Test
    func `prompt params include assistant-audience skill instructions before user text`() throws {
        let params = GooseServeClient.promptParams(
            sessionID: "session-1",
            messageID: "message-1",
            prompt: "review this",
            assistantPrompt: "Use these skills for this request: code-review.",
            personaID: "/Users/test/.agents/agents/reviewer.md"
        ).rawValue

        #expect(params["sessionId"] as? String == "session-1")
        #expect(params["messageId"] as? String == "message-1")
        #expect(params["_meta"] as? [String: String] == [
            "personaId": "/Users/test/.agents/agents/reviewer.md"
        ])
        let prompt = try #require(params["prompt"] as? [[String: Any]])
        #expect(prompt.count == 2)
        #expect(prompt[0]["type"] as? String == "text")
        #expect(prompt[0]["text"] as? String == "Use these skills for this request: code-review.")
        #expect((prompt[0]["annotations"] as? [String: [String]])?["audience"] == ["assistant"])
        #expect(prompt[1]["type"] as? String == "text")
        #expect(prompt[1]["text"] as? String == "review this")
    }

    @Test
    func `prompt params send a blank user text block when only skill instructions are present`() throws {
        let params = GooseServeClient.promptParams(
            sessionID: "session-1",
            messageID: "message-1",
            prompt: "",
            assistantPrompt: "Use these skills for this request: code-review."
        ).rawValue

        let prompt = try #require(params["prompt"] as? [[String: Any]])
        #expect(prompt.count == 2)
        #expect(prompt[1]["text"] as? String == " ")
    }

    @Test
    func `list sources params filter by source type only`() {
        let params = GooseServeClient.listSourcesParams(type: "agent").rawValue

        #expect(params as? [String: String] == ["type": "agent"])
    }

    @Test
    func `decoding source keeps content and stable path identity`() throws {
        let source = try #require(
            GooseServeClient.decodeSource([
                "type": "agent",
                "name": "block.md",
                "description": "Block guide",
                "content": "Use Block guidance.",
                "path": "/Users/test/.agents/agents/block.md",
                "global": true,
                "writable": true,
                "properties": [
                    "title": "Block",
                    "color": "#abc123"
                ]
            ])
        )

        #expect(source.id == "/Users/test/.agents/agents/block.md")
        #expect(source.content == "Use Block guidance.")
        #expect(source.title == "Block")
        #expect(source.color == "#abc123")
    }
}
