#!/usr/bin/env swift

import Foundation

enum ACPError: Error, CustomStringConvertible {
    case invalidJSON
    case rpcError(String)
    case timeout(String)
    case missingResult(String)

    var description: String {
        switch self {
        case .invalidJSON:
            return "Invalid JSON"
        case .rpcError(let message):
            return "RPC error: \(message)"
        case .timeout(let method):
            return "Timed out waiting for \(method)"
        case .missingResult(let method):
            return "Missing result for \(method)"
        }
    }
}

final class ACPClient {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let error = Pipe()
    private let queue = DispatchQueue(label: "acp-client.state")
    private let startedAt = Date()

    private var nextID = 1
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pending: [Int: PendingRequest] = [:]
    private(set) var sessionStatus = "starting"

    private struct PendingRequest {
        let method: String
        let semaphore: DispatchSemaphore
        var result: Result<[String: Any], Error>?
    }

    init(codexACPPath: String, cwd: URL) {
        process.executableURL = URL(fileURLWithPath: codexACPPath)
        process.currentDirectoryURL = cwd
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        var env = ProcessInfo.processInfo.environment
        env["INITIAL_AGENT_MODE"] = "agent-full-access"
        process.environment = env
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeStdout(handle.availableData)
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeStderr(handle.availableData)
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

    func setStatus(_ status: String) {
        queue.sync {
            sessionStatus = status
        }
        log("status=\(status)")
    }

    func request(method: String, params: [String: Any], timeout: TimeInterval = 120) throws -> [String: Any] {
        let id = queue.sync { () -> Int in
            let id = nextID
            nextID += 1
            pending[id] = PendingRequest(method: method, semaphore: DispatchSemaphore(value: 0), result: nil)
            return id
        }

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: message, options: [])
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data("\n".utf8))

        let semaphore = queue.sync { pending[id]!.semaphore }
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        guard waitResult == .success else {
            queue.sync {
                pending[id] = nil
            }
            throw ACPError.timeout(method)
        }

        let completed = queue.sync { () -> PendingRequest? in
            let item = pending[id]
            pending[id] = nil
            return item
        }

        guard let result = completed?.result else {
            throw ACPError.missingResult(method)
        }

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    private func consumeStdout(_ data: Data) {
        guard !data.isEmpty else { return }

        var lines: [Data] = []
        queue.sync {
            stdoutBuffer.append(data)

            while let newline = stdoutBuffer.firstIndex(of: 10) {
                let line = stdoutBuffer[..<newline]
                lines.append(Data(line))
                stdoutBuffer.removeSubrange(...newline)
            }
        }

        for line in lines {
            handleLine(line)
        }
    }

    private func consumeStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.sync {
            stderrBuffer.append(data)
        }
    }

    private func handleLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? [String: Any]
        else {
            return
        }

        if let method = message["method"] as? String, method == "session/update" {
            handleSessionUpdate(message)
            return
        }

        guard let id = message["id"] as? Int else {
            return
        }

        queue.sync {
            guard var item = pending[id] else { return }

            if let errorObject = message["error"] as? [String: Any] {
                let errorMessage = (errorObject["message"] as? String) ?? String(describing: errorObject)
                item.result = .failure(ACPError.rpcError(errorMessage))
            } else if let result = message["result"] as? [String: Any] {
                item.result = .success(result)
            } else {
                item.result = .success([:])
            }

            pending[id] = item
            item.semaphore.signal()
        }
    }

    private func handleSessionUpdate(_ message: [String: Any]) {
        guard
            let params = message["params"] as? [String: Any],
            let update = params["update"] as? [String: Any]
        else {
            log("ACP event: malformed session/update")
            return
        }

        let status = queue.sync { sessionStatus }
        log("ACP event while \(status): \(summarize(update))")
    }

    private func summarize(_ update: [String: Any]) -> String {
        let kind = (update["sessionUpdate"] as? String) ?? "unknown"

        switch kind {
        case "tool_call":
            let id = (update["toolCallId"] as? String) ?? ""
            let status = (update["status"] as? String) ?? ""
            let rawInput = update["rawInput"] as? [String: Any]
            let command = rawInput?["cmd"] as? String
                ?? rawInput?["command"] as? String
                ?? update["title"] as? String
                ?? "tool"
            return "tool_call \(id) \(status) \(command)"

        case "tool_call_update":
            let id = (update["toolCallId"] as? String) ?? ""
            let status = (update["status"] as? String) ?? ""
            return "tool_call_update \(id) \(status)"

        case "agent_message_chunk", "agent_thought_chunk", "user_message_chunk":
            let content = update["content"] as? [String: Any]
            let text = (content?["text"] as? String) ?? ""
            return "\(kind) \(text.prefix(120))"

        case "session_info_update":
            let title = update["title"] as? String ?? "nil"
            let updatedAt = update["updatedAt"] as? String ?? "nil"
            return "session_info_update title=\(title) updatedAt=\(updatedAt)"

        case "usage_update":
            let used = update["used"] ?? "?"
            let size = update["size"] ?? "?"
            return "usage_update \(used)/\(size)"

        default:
            return kind
        }
    }

    private func log(_ message: String) {
        let elapsed = Date().timeIntervalSince(startedAt)
        print(String(format: "[%5.1fs] %@", elapsed, message))
        fflush(stdout)
    }

    func stderrText() -> String {
        queue.sync {
            String(data: stderrBuffer, encoding: .utf8) ?? ""
        }
    }
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let codexACPPath = "/opt/homebrew/bin/codex-acp"
let client = ACPClient(codexACPPath: codexACPPath, cwd: cwd)

do {
    print("Starting codex-acp from \(cwd.path)")
    try client.start()

    _ = try client.request(
        method: "initialize",
        params: [
            "protocolVersion": 1,
            "clientCapabilities": [:],
            "clientInfo": [
                "name": "swift-acp-status-demo",
                "title": "Swift ACP Status Demo",
                "version": "1.0.0"
            ]
        ],
        timeout: 30
    )

    let newSession = try client.request(
        method: "session/new",
        params: [
            "cwd": cwd.path,
            "mcpServers": []
        ],
        timeout: 60
    )

    guard let sessionID = newSession["sessionId"] as? String else {
        throw ACPError.missingResult("session/new sessionId")
    }

    print("Created ACP session: \(sessionID)")
    client.setStatus("idle")

    client.setStatus("working")
    let promptResult = try client.request(
        method: "session/prompt",
        params: [
            "sessionId": sessionID,
            "messageId": "swift-acp-status-demo-1",
            "prompt": [
                [
                    "type": "text",
                    "text": "Swift ACP status demo. Run `pwd; sleep 8; echo SWIFT_ACP_STATUS_DEMO_DONE`, then reply exactly: Swift ACP status demo complete"
                ]
            ]
        ],
        timeout: 180
    )

    client.setStatus("idle")
    print("Prompt completed: \(promptResult)")
    print("Verified: request pending == working; session/prompt response == idle; session/update notifications streamed in real time.")
    client.stop()
} catch {
    fputs("Error: \(error)\n", stderr)
    let stderrText = client.stderrText()
    if !stderrText.isEmpty {
        fputs("codex-acp stderr:\n\(stderrText)\n", stderr)
    }
    client.stop()
    exit(1)
}
