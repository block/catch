import Foundation

enum GooseServeClientError: Error, Equatable, LocalizedError {
    case executableNotFound([String])
    case connectionNotOpen
    case embeddedServerURLMissing
    case embeddedServerTokenMissing
    case invalidEmbeddedServerURL(String)
    case invalidResponse(String)
    case rpcError(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let paths):
            return "Goose executable was not found. Checked: \(paths.joined(separator: ", "))."
        case .connectionNotOpen:
            return "Goose server connection is not open."
        case .embeddedServerURLMissing:
            return "Embedded Catch requires GOOSE_SERVE_URL."
        case .embeddedServerTokenMissing:
            return "Embedded Catch requires GOOSE_SERVE_URL to include a token."
        case .invalidEmbeddedServerURL(let value):
            return "Embedded Catch could not parse GOOSE_SERVE_URL: \(value)."
        case .invalidResponse(let method):
            return "Invalid Goose response for \(method)."
        case .rpcError(let message):
            return message
        case .timeout(let method):
            return "Timed out waiting for \(method)."
        }
    }
}

struct GooseSessionConfiguration: Equatable {
    var providerID: String?
    var modelID: String?
    var cwd: String
    var projectID: String?
    var reasoningEffort: String?
    var invokedAgent: GooseInvokedAgent?
    var invokedSkills: [GooseInvokedSkill] = []
}

struct GooseInvokedAgent: Equatable, Sendable {
    let personaID: String
    let displayName: String
    let systemPrompt: String?
}

struct GooseInvokedSkill: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
}

struct GooseSessionCreationMetadata: Sendable {
    var projectSources: [GooseSourceEntry]
    var agentSources: [GooseSourceEntry]
    var skillSources: [GooseSourceEntry]
    var providers: [GooseProviderEntry]
    var supportedModels: [GooseSupportedModel]
    var defaults: GooseProviderDefaults?
}

struct GooseSourceEntry: Identifiable, Equatable, Sendable {
    var id: String { path ?? "\(type):\(name)" }

    let type: String
    let name: String
    let description: String
    let content: String
    let path: String?
    let global: Bool
    let writable: Bool
    let title: String?
    let color: String?
}

struct GooseProviderDefaults: Equatable, Sendable {
    let providerID: String
    let modelID: String
}

struct GooseProviderEntry: Identifiable, Equatable, Sendable {
    var id: String { providerID }

    let providerID: String
    let providerName: String
    let defaultModelID: String?
    let configured: Bool
    let models: [GooseProviderModel]
}

struct GooseProviderModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let recommended: Bool
    let reasoning: Bool
}

struct GooseSupportedModel: Identifiable, Equatable, Sendable {
    let id: String
}

final class GooseServeClient: NSObject, @unchecked Sendable {
    typealias UpdateHandler = (SessionUpdateEvent) -> Void

    enum LaunchMode: Equatable, Sendable {
        case standalone
        case embedded
    }

    private struct PendingRequest {
        let method: String
        let completion: (Result<JSONObject, Error>) -> Void
    }

    struct EmbeddedServerConfiguration: Equatable {
        static let serveURLEnvironmentKey = "GOOSE_SERVE_URL"

        let webSocketURL: URL

        init(environment: [String: String]) throws {
            guard let rawURL = environment[Self.serveURLEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawURL.isEmpty
            else {
                throw GooseServeClientError.embeddedServerURLMissing
            }

            guard let components = URLComponents(string: rawURL),
                  let scheme = components.scheme,
                  scheme == "ws" || scheme == "wss",
                  components.host != nil
            else {
                throw GooseServeClientError.invalidEmbeddedServerURL(rawURL)
            }

            let hasToken = components.queryItems?.contains {
                $0.name == "token" && $0.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            } == true
            if !hasToken {
                throw GooseServeClientError.embeddedServerTokenMissing
            }

            guard let webSocketURL = components.url else {
                throw GooseServeClientError.invalidEmbeddedServerURL(rawURL)
            }

            self.webSocketURL = webSocketURL
        }
    }

    private let executablePaths: [String]
    private let host = "127.0.0.1"
    private let port: Int
    private let launchMode: LaunchMode
    private let environment: [String: String]
    private let queue = DispatchQueue(label: "Catch.GooseServeClient")
    private let process = Process()
    private let stderr = Pipe()
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]
    private var updateHandler: UpdateHandler?
    private var isOpen = false

    init(
        port: Int = 32845,
        executablePaths: [String]? = nil,
        launchMode: LaunchMode = .standalone,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.port = port
        self.launchMode = launchMode
        self.environment = environment
        self.executablePaths = executablePaths ?? GooseServeClient.defaultExecutablePaths()
        super.init()
    }

    func start(onUpdate: @escaping UpdateHandler) async throws {
        updateHandler = onUpdate
        if launchMode == .standalone {
            try startServer()
        } else {
            _ = try webSocketURL()
        }
        try await connectWithRetry()
    }

    func stop() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        failAllPending(GooseServeClientError.connectionNotOpen)

        if process.isRunning {
            process.terminate()
        }
    }

    func initialize() async throws {
        _ = try await request(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "goose": [
                        "unstable": true
                    ]
                ],
                "clientInfo": [
                    "name": "catch",
                    "title": "Catch",
                    "version": "1.0.0"
                ]
            ],
            timeout: 30
        )
    }

    func listSessions() async throws -> [Session] {
        let response = try await request(
            method: "session/list",
            params: [
                "cursor": NSNull(),
                "cwd": NSNull()
            ],
            timeout: 30
        )

        guard let rawSessions = response["sessions"] as? [[String: Any]] else {
            throw GooseServeClientError.invalidResponse("session/list")
        }

        return rawSessions.compactMap { decodeSession(JSONObject($0)) }
    }

    func createSession(configuration: GooseSessionConfiguration) async throws -> String {
        let newResponse = try await request(
            method: "session/new",
            params: Self.newSessionParams(configuration: configuration),
            timeout: 60
        )

        guard let sessionID = newResponse["sessionId"] as? String else {
            throw GooseServeClientError.invalidResponse("session/new")
        }

        if let providerID = configuration.providerID {
            try await setConfigOption(sessionID: sessionID, configID: "provider", value: providerID)
        }

        if let modelID = configuration.modelID {
            try await setConfigOption(sessionID: sessionID, configID: "model", value: modelID)
        }

        if let reasoningEffort = configuration.reasoningEffort {
            try? await setConfigOption(sessionID: sessionID, configID: "thinking_effort", value: reasoningEffort)
        }

        if let projectID = configuration.projectID {
            try await updateProject(sessionID: sessionID, projectID: projectID)
        }

        if let systemPrompt = configuration.invokedAgent?.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !systemPrompt.isEmpty
        {
            try await appendSessionSystemPrompt(
                sessionID: sessionID,
                key: "client_system_prompt",
                text: systemPrompt
            )
        }

        return sessionID
    }

    func loadSessionCreationMetadata() async throws -> GooseSessionCreationMetadata {
        async let projectSources = listSources(type: "project")
        async let agentSources = listSources(type: "agent")
        async let skillSources = listSkillSources()
        async let providers = listProviders(providerIDs: ["databricks_v2"])
        async let defaults = readDefaults()
        async let supportedModels = listSupportedModels(providerID: "databricks_v2")

        return try await GooseSessionCreationMetadata(
            projectSources: projectSources,
            agentSources: agentSources,
            skillSources: skillSources,
            providers: providers,
            supportedModels: supportedModels,
            defaults: defaults
        )
    }

    func sendPrompt(
        sessionID: String,
        prompt: String,
        assistantPrompt: String? = nil,
        personaID: String? = nil
    ) async throws {
        _ = try await request(
            method: "session/prompt",
            params: Self.promptParams(
                sessionID: sessionID,
                messageID: UUID().uuidString,
                prompt: prompt,
                assistantPrompt: assistantPrompt,
                personaID: personaID
            ),
            timeout: 300
        )
    }

    private func setConfigOption(sessionID: String, configID: String, value: String) async throws {
        _ = try await request(
            method: "session/set_config_option",
            params: [
                "sessionId": sessionID,
                "configId": configID,
                "value": value
            ],
            timeout: 30
        )
    }

    private func updateProject(sessionID: String, projectID: String) async throws {
        _ = try await request(
            method: "_goose/unstable/session/project/update",
            params: [
                "sessionId": sessionID,
                "projectId": projectID
            ],
            timeout: 30
        )
    }

    private func appendSessionSystemPrompt(sessionID: String, key: String, text: String) async throws {
        _ = try await request(
            method: "_goose/unstable/session/system-prompt/set",
            params: Self.appendSystemPromptParams(sessionID: sessionID, key: key, text: text),
            timeout: 30
        )
    }

    static func newSessionParams(configuration: GooseSessionConfiguration) -> JSONObject {
        var params: [String: Any] = [
            "cwd": configuration.cwd,
            "mcpServers": []
        ]

        var meta: [String: String] = [:]
        if let providerID = configuration.providerID {
            meta["provider"] = providerID
        }
        if let projectID = configuration.projectID {
            meta["projectId"] = projectID
        }
        if let personaID = configuration.invokedAgent?.personaID {
            meta["personaId"] = personaID
        }
        if !meta.isEmpty {
            params["_meta"] = meta
        }

        return JSONObject(params)
    }

    static func appendSystemPromptParams(sessionID: String, key: String, text: String) -> JSONObject {
        JSONObject([
            "sessionId": sessionID,
            "mode": "append",
            "key": key,
            "text": text
        ])
    }

    static func promptParams(
        sessionID: String,
        messageID: String,
        prompt: String,
        assistantPrompt: String? = nil,
        personaID: String? = nil
    ) -> JSONObject {
        var content: [[String: Any]] = []
        if let assistantText = assistantPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !assistantText.isEmpty
        {
            content.append([
                "type": "text",
                "text": assistantText,
                "annotations": [
                    "audience": ["assistant"]
                ]
            ])
        }

        content.append([
            "type": "text",
            "text": prompt.isEmpty ? " " : prompt
        ])

        var params: [String: Any] = [
            "sessionId": sessionID,
            "messageId": messageID,
            "prompt": content
        ]

        if let personaID = personaID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !personaID.isEmpty
        {
            params["_meta"] = [
                "personaId": personaID
            ]
        }

        return JSONObject(params)
    }

    static func skillAssistantPrompt(skills: [GooseInvokedSkill]) -> String? {
        let skillNames = skills
            .map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !skillNames.isEmpty else { return nil }
        return "Use these skills for this request: \(skillNames.joined(separator: ", "))."
    }

    static func listSourcesParams(type: String? = nil, projectDir: String? = nil) -> JSONObject {
        var params: [String: Any] = [:]
        if let type {
            params["type"] = type
        }
        if let projectDir {
            params["projectDir"] = projectDir
        }
        return JSONObject(params)
    }

    private func listSources(type: String? = nil, projectDir: String? = nil) async throws -> [GooseSourceEntry] {
        let response = try await request(
            method: "_goose/unstable/sources/list",
            params: Self.listSourcesParams(type: type, projectDir: projectDir),
            timeout: 30
        )

        guard let rawSources = response["sources"] as? [[String: Any]] else {
            throw GooseServeClientError.invalidResponse("_goose/unstable/sources/list")
        }

        return rawSources.compactMap(Self.decodeSource)
    }

    private func listSkillSources() async throws -> [GooseSourceEntry] {
        async let globalSkills = listSources(type: "skill")
        async let builtinSkills = listSources(type: "builtinSkill")
        return try await (globalSkills + builtinSkills).deduplicatedByID()
    }

    private func listProviders(providerIDs: [String]? = nil) async throws -> [GooseProviderEntry] {
        let params: JSONObject = if let providerIDs {
            ["providerIds": providerIDs]
        } else {
            [:]
        }

        let response = try await request(
            method: "_goose/unstable/providers/list",
            params: params,
            timeout: 30
        )

        guard let rawEntries = response["entries"] as? [[String: Any]] else {
            throw GooseServeClientError.invalidResponse("_goose/unstable/providers/list")
        }

        return rawEntries.compactMap(Self.decodeProvider)
    }

    private func listSupportedModels(providerID: String) async throws -> [GooseSupportedModel] {
        let response = try await request(
            method: "_goose/unstable/providers/supported-models/list",
            params: [
                "providerId": providerID
            ],
            timeout: 30
        )

        guard let rawModels = response["models"] as? [String] else {
            throw GooseServeClientError.invalidResponse("_goose/unstable/providers/supported-models/list")
        }

        return rawModels.map(GooseSupportedModel.init(id:))
    }

    private func readDefaults() async throws -> GooseProviderDefaults? {
        let response = try await request(
            method: "_goose/unstable/defaults/read",
            params: [:],
            timeout: 30
        )

        guard let providerID = response["providerId"] as? String,
              let modelID = response["modelId"] as? String
        else {
            return nil
        }

        return GooseProviderDefaults(providerID: providerID, modelID: modelID)
    }

    private func startServer() throws {
        if process.isRunning {
            return
        }

        guard let executablePath = executablePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw GooseServeClientError.executableNotFound(executablePaths)
        }

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["serve", "--host", host, "--port", "\(port)"]
        process.standardError = stderr

        var environment = ProcessInfo.processInfo.environment
        environment.removeAppBundleIdentity()
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["GOOSE_SERVER__SECRET_KEY"] = UUID().uuidString
        process.environment = environment

        try process.run()
    }

    private func connect() async throws {
        let delegate = WebSocketDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: try webSocketURL())
        webSocketTask = task

        task.resume()
        try await delegate.waitForOpen(timeout: 10)

        queue.async {
            self.isOpen = true
        }

        receiveLoop()
    }

    private func webSocketURL() throws -> URL {
        switch launchMode {
        case .standalone:
            return URL(string: "ws://\(host):\(port)/acp")!
        case .embedded:
            return try EmbeddedServerConfiguration(environment: environment).webSocketURL
        }
    }

    private func connectWithRetry() async throws {
        let deadline = Date().addingTimeInterval(10)
        var lastError: Error?

        repeat {
            do {
                try await connect()
                return
            } catch {
                lastError = error
                webSocketTask?.cancel(with: .goingAway, reason: nil)
                session?.invalidateAndCancel()
                webSocketTask = nil
                session = nil

                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        } while Date() < deadline

        throw lastError ?? GooseServeClientError.timeout("websocket open")
    }

    private func request(method: String, params: JSONObject, timeout: TimeInterval) async throws -> JSONObject {
        let id = nextRequestID()
        let message: JSONObject = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: message.rawValue)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GooseServeClientError.invalidResponse(method)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONObject, Error>) in
            queue.async {
                guard self.isOpen, let webSocketTask = self.webSocketTask else {
                    continuation.resume(throwing: GooseServeClientError.connectionNotOpen)
                    return
                }

                self.pending[id] = PendingRequest(method: method) { result in
                    continuation.resume(with: result)
                }

                webSocketTask.send(.string(text)) { error in
                    guard let error else { return }

                    self.queue.async {
                        guard let pending = self.pending[id] else { return }
                        self.pending[id] = nil
                        pending.completion(.failure(error))
                    }
                }

                self.queue.asyncAfter(deadline: .now() + timeout) {
                    guard let pending = self.pending[id] else { return }
                    self.pending[id] = nil
                    pending.completion(.failure(GooseServeClientError.timeout(method)))
                }
            }
        }
    }

    private func nextRequestID() -> Int {
        queue.sync {
            let id = nextID
            nextID += 1
            return id
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                handle(message)
                receiveLoop()
            case .failure(let error):
                queue.async {
                    self.isOpen = false
                    self.failAllPending(error)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let string):
            data = Data(string.utf8)
        case .data(let payload):
            data = payload
        @unknown default:
            data = nil
        }

        guard let data else { return }

        queue.async {
            self.handleMessageData(data)
        }
    }

    private func handleMessageData(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? [String: Any]
        else {
            return
        }

        let jsonMessage = JSONObject(message)

        if let method = jsonMessage["method"] as? String {
            if method == "session/update" || method == "_goose/unstable/session/update" {
                handleUpdate(jsonMessage)
            }
            return
        }

        guard let id = (jsonMessage["id"] as? NSNumber)?.intValue, let pending = pending[id] else {
            return
        }

        self.pending[id] = nil

        if let error = jsonMessage["error"] as? [String: Any] {
            let message = error["message"] as? String ?? String(describing: error)
            pending.completion(.failure(GooseServeClientError.rpcError(message)))
        } else if let result = jsonMessage["result"] as? [String: Any] {
            pending.completion(.success(JSONObject(result)))
        } else {
            pending.completion(.success([:]))
        }
    }

    private func failAllPending(_ error: Error) {
        let pendingRequests = pending.values
        pending.removeAll()
        for request in pendingRequests {
            request.completion(.failure(error))
        }
    }

    private func handleUpdate(_ message: JSONObject) {
        guard
            let params = message["params"] as? [String: Any],
            let sessionID = params["sessionId"] as? String,
            let update = params["update"] as? [String: Any]
        else {
            return
        }

        let jsonUpdate = JSONObject(update)
        let timestamp = Date()

        updateHandler?(
            SessionUpdateEvent(
                provider: .goose,
                sessionID: sessionID,
                status: Self.status(for: jsonUpdate),
                summary: Self.summarize(jsonUpdate),
                timestamp: timestamp,
                isMessageActivity: Self.isMessageActivity(jsonUpdate)
            )
        )
    }

    static func decodeSource(_ object: [String: Any]) -> GooseSourceEntry? {
        guard let type = object["type"] as? String,
              let name = object["name"] as? String
        else {
            return nil
        }

        let properties = object["properties"] as? [String: Any]
        return GooseSourceEntry(
            type: type,
            name: name,
            description: object["description"] as? String ?? "",
            content: object["content"] as? String ?? "",
            path: object["path"] as? String,
            global: boolValue(object["global"]),
            writable: boolValue(object["writable"]),
            title: properties?["title"] as? String,
            color: properties?["color"] as? String
        )
    }

    private static func decodeProvider(_ object: [String: Any]) -> GooseProviderEntry? {
        guard let providerID = object["providerId"] as? String else {
            return nil
        }

        let rawModels = object["models"] as? [[String: Any]] ?? []
        return GooseProviderEntry(
            providerID: providerID,
            providerName: object["providerName"] as? String ?? providerID,
            defaultModelID: object["defaultModel"] as? String,
            configured: boolValue(object["configured"]),
            models: rawModels.compactMap(decodeProviderModel)
        )
    }

    private static func decodeProviderModel(_ object: [String: Any]) -> GooseProviderModel? {
        guard let id = object["id"] as? String else {
            return nil
        }

        return GooseProviderModel(
            id: id,
            name: object["name"] as? String ?? id,
            recommended: boolValue(object["recommended"]),
            reasoning: boolValue(object["reasoning"])
        )
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool:
            value
        case let value as NSNumber:
            value.boolValue
        case let value as String:
            ["1", "true", "yes"].contains(value.lowercased())
        default:
            false
        }
    }

    private func decodeSession(_ object: JSONObject) -> Session? {
        guard let id = object["sessionId"] as? String ?? object["id"] as? String else {
            return nil
        }

        let meta = (object["_meta"] as? [String: Any]).map(JSONObject.init)
        let isArchived = (meta?["archivedAt"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        let title = object["title"] as? String
            ?? object["name"] as? String
            ?? object["summary"] as? String
            ?? ""
        let cwd = object["cwd"] as? String
            ?? object["workingDirectory"] as? String
            ?? object["projectPath"] as? String
            ?? ""
        let updatedAt = (object["updatedAt"] as? String).flatMap(Self.parseACPDate)
            ?? (object["lastModified"] as? String).flatMap(Self.parseACPDate)
            ?? (object["createdAt"] as? String).flatMap(Self.parseACPDate)
            ?? (meta?["createdAt"] as? String).flatMap(Self.parseACPDate)
        let lastMessageAt = (object["lastMessageAt"] as? String).flatMap(Self.parseACPDate)
            ?? (meta?["lastMessageAt"] as? String).flatMap(Self.parseACPDate)

        let providerID = meta?["providerId"] as? String
        let modelID = meta?["modelId"] as? String

        return Session(
            provider: .goose,
            sessionID: id,
            cwd: cwd,
            title: title,
            updatedAt: updatedAt,
            lastMessageAt: lastMessageAt,
            status: .idle,
            lastEvent: [providerID, modelID].compactMap { $0 }.joined(separator: " / "),
            isArchived: isArchived
        )
    }

    private static func isMessageActivity(_ update: JSONObject) -> Bool {
        switch update["sessionUpdate"] as? String {
        case "agent_message", "agent_message_chunk", "user_message", "user_message_chunk":
            return true
        default:
            return false
        }
    }

    private static func status(for update: JSONObject) -> SessionStatus {
        let kind = (update["sessionUpdate"] as? String ?? "").lowercased()
        let rawStatus = update["status"] as? String ?? ""
        let normalizedStatus = rawStatus.lowercased()
        let stopReason = (update["stopReason"] as? String ?? "").lowercased()

        if [
            "complete",
            "completed",
            "done",
            "failed",
            "cancelled",
            "canceled"
        ].contains(normalizedStatus) || !stopReason.isEmpty {
            return .idle
        }

        if [
            "task_complete",
            "turn_complete",
            "session_idle",
            "agent_turn_complete",
            "session_info_update",
            "agent_message",
            "agent_message_chunk"
        ].contains(kind) {
            return .idle
        }

        return .working
    }

    private static func summarize(_ update: JSONObject) -> String {
        let kind = update["sessionUpdate"] as? String ?? "session/update"

        switch kind {
        case "tool_call":
            let status = update["status"] as? String ?? "in_progress"
            let rawInput = (update["rawInput"] as? [String: Any]).map(JSONObject.init)
            let command = rawInput?["cmd"] as? String
                ?? rawInput?["command"] as? String
                ?? update["title"] as? String
                ?? "tool"
            return "Tool \(status): \(command)"
        case "tool_call_update":
            let status = update["status"] as? String ?? "updated"
            return "Tool \(status)"
        case "agent_message", "agent_message_chunk":
            return "Assistant message"
        case "usage_update":
            return "Usage updated"
        case "status_message":
            return update["message"] as? String ?? "Status updated"
        default:
            return kind
        }
    }

    private static func parseACPDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func defaultExecutablePaths() -> [String] {
        [
            ProcessInfo.processInfo.environment["GOOSE_BINARY"],
            "/usr/local/bin/goose",
            "/opt/homebrew/bin/goose",
            "/opt/homebrew/lib/node_modules/@aaif/goose/node_modules/@aaif/goose-binary-darwin-arm64/bin/goose",
            "/opt/homebrew/lib/node_modules/@aaif/goose/node_modules/@aaif/goose-binary-darwin-x64/bin/goose",
            "/usr/local/lib/node_modules/@aaif/goose/node_modules/@aaif/goose-binary-darwin-arm64/bin/goose",
            "/usr/local/lib/node_modules/@aaif/goose/node_modules/@aaif/goose-binary-darwin-x64/bin/goose"
        ].compactMap { $0 }
    }
}

private extension Dictionary where Key == String, Value == String {
    mutating func removeAppBundleIdentity() {
        self["__CFBundleIdentifier"] = nil
        self["XPC_FLAGS"] = nil
        self["XPC_SERVICE_NAME"] = nil
        self["LaunchInstanceID"] = nil
    }
}

private extension Array where Element == GooseSourceEntry {
    func deduplicatedByID() -> [GooseSourceEntry] {
        var seen: Set<String> = []
        var unique: [GooseSourceEntry] = []

        for source in self where seen.insert(source.id).inserted {
            unique.append(source)
        }

        return unique
    }
}

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let continuationQueue = DispatchQueue(label: "Catch.GooseServeClient.WebSocketDelegate")
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var didOpen = false
    private var completedWithError: Error?

    func waitForOpen(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            continuationQueue.async {
                if self.didOpen {
                    continuation.resume()
                    return
                }

                if let completedWithError = self.completedWithError {
                    continuation.resume(throwing: completedWithError)
                    return
                }

                self.openContinuation = continuation
                self.continuationQueue.asyncAfter(deadline: .now() + timeout) {
                    guard let openContinuation = self.openContinuation else { return }
                    self.openContinuation = nil
                    openContinuation.resume(throwing: GooseServeClientError.timeout("websocket open"))
                }
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        continuationQueue.async {
            self.didOpen = true

            if let openContinuation = self.openContinuation {
                self.openContinuation = nil
                openContinuation.resume()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }

        continuationQueue.async {
            self.completedWithError = error

            if let openContinuation = self.openContinuation {
                self.openContinuation = nil
                openContinuation.resume(throwing: error)
            }
        }
    }
}
