import Foundation

enum ACPClientError: Error, LocalizedError {
    case executableNotFound(String, [String])
    case processNotRunning
    case invalidResponse(String)
    case rpcError(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let provider, let paths):
            return "\(provider) ACP executable was not found. Checked: \(paths.joined(separator: ", "))."
        case .processNotRunning:
            return "ACP server is not running."
        case .invalidResponse(let method):
            return "Invalid ACP response for \(method)."
        case .rpcError(let message):
            return message
        case .timeout(let method):
            return "Timed out waiting for \(method)."
        }
    }
}

struct ACPClientConfiguration {
    var provider: AgentProvider
    var executablePaths: [String]
    var arguments: [String] = []
    var environment: [String: String] = [:]

    var displayName: String {
        provider.displayName
    }

    func resolvedExecutablePath() -> String? {
        executablePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

final class ACPClient {
    typealias JSONObject = [String: Any]
    typealias UpdateHandler = (SessionUpdateEvent) -> Void

    private struct PendingRequest {
        let method: String
        let completion: (Result<JSONObject, Error>) -> Void
    }

    private let configuration: ACPClientConfiguration
    private let cwd: URL
    private let queue: DispatchQueue
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let error = Pipe()

    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]
    private var updateHandler: UpdateHandler?

    init(
        configuration: ACPClientConfiguration,
        cwd: URL
    ) {
        self.configuration = configuration
        self.cwd = cwd
        self.queue = DispatchQueue(label: "Catch.ACPClient.\(configuration.provider.rawValue)")
    }

    func start(onUpdate: @escaping UpdateHandler) throws {
        guard let executablePath = configuration.resolvedExecutablePath() else {
            throw ACPClientError.executableNotFound(configuration.displayName, configuration.executablePaths)
        }

        updateHandler = onUpdate
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = configuration.arguments
        process.currentDirectoryURL = cwd
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        configuration.environment.forEach { key, value in
            environment[key] = value
        }
        environment["INITIAL_AGENT_MODE"] = "agent-full-access"
        process.environment = environment

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeStderr(handle.availableData)
        }
        process.terminationHandler = { [weak self] process in
            self?.queue.async {
                let message = "\(self?.configuration.displayName ?? "ACP") exited with status \(process.terminationStatus)"
                self?.failAllPending(ACPClientError.rpcError(message))
            }
        }

        try process.run()
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()

        if process.isRunning {
            process.terminate()
        }
    }

    func initialize() async throws {
        _ = try await request(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientCapabilities": [:],
                "clientInfo": [
                    "name": "codex-sessions-macos",
                    "title": "Catch",
                    "version": "1.0.0"
                ]
            ],
            timeout: 30
        )
    }

    func listSessions() async throws -> (sessions: [CodexSession], nextCursor: String?) {
        let response = try await request(
            method: "session/list",
            params: [
                "cursor": NSNull(),
                "cwd": NSNull()
            ],
            timeout: 30
        )

        guard let rawSessions = response["sessions"] as? [JSONObject] else {
            throw ACPClientError.invalidResponse("session/list")
        }

        let sessions = rawSessions.compactMap { decodeSession($0) }
        let cursor = response["nextCursor"] as? String
        return (sessions, cursor)
    }

    func createSession() async throws -> String {
        let response = try await request(
            method: "session/new",
            params: [
                "cwd": cwd.path,
                "mcpServers": []
            ],
            timeout: 60
        )

        guard let sessionID = response["sessionId"] as? String else {
            throw ACPClientError.invalidResponse("session/new")
        }

        return sessionID
    }

    func sendPrompt(sessionID: String, prompt: String) async throws {
        _ = try await request(
            method: "session/prompt",
            params: [
                "sessionId": sessionID,
                "messageId": UUID().uuidString,
                "prompt": [
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ],
            timeout: 300
        )
    }

    private func request(method: String, params: JSONObject, timeout: TimeInterval) async throws -> JSONObject {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.process.isRunning else {
                    continuation.resume(throwing: ACPClientError.processNotRunning)
                    return
                }

                let id = self.nextID
                self.nextID += 1
                self.pending[id] = PendingRequest(method: method) { result in
                    continuation.resume(with: result)
                }

                let message: JSONObject = [
                    "jsonrpc": "2.0",
                    "id": id,
                    "method": method,
                    "params": params
                ]

                do {
                    let data = try JSONSerialization.data(withJSONObject: message)
                    self.input.fileHandleForWriting.write(data)
                    self.input.fileHandleForWriting.write(Data("\n".utf8))
                } catch {
                    self.pending[id] = nil
                    continuation.resume(throwing: error)
                    return
                }

                self.queue.asyncAfter(deadline: .now() + timeout) {
                    guard let pending = self.pending[id] else { return }
                    self.pending[id] = nil
                    pending.completion(.failure(ACPClientError.timeout(method)))
                }
            }
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }

        queue.async {
            self.stdoutBuffer.append(data)
            while let newlineIndex = self.stdoutBuffer.firstIndex(of: 10) {
                let line = self.stdoutBuffer[..<newlineIndex]
                self.stdoutBuffer.removeSubrange(...newlineIndex)
                self.handleLine(Data(line))
            }
        }
    }

    private func consumeStderr(_ data: Data) {
        guard !data.isEmpty else { return }

        queue.async {
            self.stderrBuffer.append(data)
            if self.stderrBuffer.count > 16_384 {
                self.stderrBuffer.removeFirst(self.stderrBuffer.count - 16_384)
            }
        }
    }

    private func handleLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? JSONObject
        else {
            return
        }

        if let method = message["method"] as? String, method == "session/update" {
            handleUpdate(message)
            return
        }

        guard let id = (message["id"] as? NSNumber)?.intValue, let pending = pending[id] else {
            return
        }

        self.pending[id] = nil

        if let error = message["error"] as? JSONObject {
            let message = error["message"] as? String ?? String(describing: error)
            pending.completion(.failure(ACPClientError.rpcError(message)))
        } else if let result = message["result"] as? JSONObject {
            pending.completion(.success(result))
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
            let params = message["params"] as? JSONObject,
            let sessionID = params["sessionId"] as? String,
            let update = params["update"] as? JSONObject
        else {
            return
        }

        updateHandler?(
            SessionUpdateEvent(
                provider: configuration.provider,
                sessionID: sessionID,
                status: Self.status(for: update),
                summary: Self.summarize(update),
                timestamp: Date()
            )
        )
    }

    private static func status(for update: JSONObject) -> SessionStatus {
        let kind = (update["sessionUpdate"] as? String ?? "").lowercased()
        let rawStatus = update["status"] as? String ?? ""
        let normalizedStatus = rawStatus.lowercased()

        if [
            "complete",
            "completed",
            "done",
            "failed",
            "cancelled",
            "canceled"
        ].contains(normalizedStatus) {
            return .idle
        }

        if [
            "task_complete",
            "turn_complete",
            "session_idle",
            "agent_turn_complete"
        ].contains(kind) {
            return .idle
        }

        return .working
    }

    private func decodeSession(_ object: JSONObject) -> CodexSession? {
        guard let id = object["sessionId"] as? String ?? object["id"] as? String else {
            return nil
        }

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

        return CodexSession(
            provider: configuration.provider,
            sessionID: id,
            cwd: cwd,
            title: title,
            updatedAt: updatedAt,
            status: .idle,
            lastEvent: "Listed by \(configuration.displayName)"
        )
    }

    private static func summarize(_ update: JSONObject) -> String {
        let kind = update["sessionUpdate"] as? String ?? "session/update"

        switch kind {
        case "tool_call":
            let status = update["status"] as? String ?? "in_progress"
            let rawInput = update["rawInput"] as? JSONObject
            let command = rawInput?["cmd"] as? String
                ?? rawInput?["command"] as? String
                ?? update["title"] as? String
                ?? "tool"
            return "Tool \(status): \(command)"
        case "tool_call_update":
            let status = update["status"] as? String ?? "updated"
            return "Tool \(status)"
        case "agent_message_chunk":
            let content = update["content"] as? JSONObject
            let text = content?["text"] as? String ?? ""
            return text.isEmpty ? "Assistant message" : text
        case "usage_update":
            return "Usage updated"
        case "session_info_update":
            return "Session info updated"
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
}
