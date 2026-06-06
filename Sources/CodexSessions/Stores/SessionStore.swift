import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [CodexSession] = []
    @Published var selectedSessionID: String? {
        didSet {
            ensureSelection()
        }
    }
    @Published var prompt = ""
    @Published var isConnected = false
    @Published var errorMessage: String?

    private struct ProviderClient {
        let configuration: ACPClientConfiguration
        let client: ACPClient
    }

    private let workspaceURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("CodexSessions/Workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private var clients: [ProviderClient] = []
    private var refreshTask: Task<Void, Never>?

    var selectedSession: CodexSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    func start() async {
        guard clients.isEmpty else { return }

        var startupErrors: [String] = []

        for configuration in Self.providerConfigurations() {
            let client = ACPClient(configuration: configuration, cwd: workspaceURL)
            clients.append(ProviderClient(configuration: configuration, client: client))

            do {
            try client.start { [weak self] event in
                Task { @MainActor in
                    self?.apply(event)
                }
            }
            try await client.initialize()
            } catch {
                startupErrors.append("\(configuration.displayName): \(error.localizedDescription)")
                client.stop()
                clients.removeAll { $0.configuration.provider == configuration.provider }
            }
        }

        isConnected = !clients.isEmpty
        errorMessage = startupErrors.isEmpty ? nil : startupErrors.joined(separator: "\n")
        await refreshSessions()
        startPolling()

        NotificationCenter.default.addObserver(forName: .appWillTerminateProcessClients, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.clients.forEach { $0.client.stop() }
            }
        }
    }

    func refreshSessions() async {
        guard !clients.isEmpty else { return }

        var listed: [CodexSession] = []
        var refreshErrors: [String] = []

        for providerClient in clients {
            do {
                let response = try await providerClient.client.listSessions()
                listed.append(contentsOf: response.sessions)
            } catch {
                refreshErrors.append("\(providerClient.configuration.displayName): \(error.localizedDescription)")
            }
        }

        mergeListedSessions(listed)
        errorMessage = refreshErrors.isEmpty ? nil : refreshErrors.joined(separator: "\n")
    }

    func submitPrompt() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedPrompt.isEmpty,
            let providerClient = clients.first(where: { $0.configuration.provider == .codex })
        else { return }

        prompt = ""
        errorMessage = nil

        do {
            let sessionID = try await providerClient.client.createSession()
            upsert(
                CodexSession(
                    provider: providerClient.configuration.provider,
                    sessionID: sessionID,
                    cwd: workspaceURL.path,
                    title: String(trimmedPrompt.prefix(80)),
                    updatedAt: Date(),
                    status: .working,
                    lastEvent: "Prompt sent"
                )
            )

            try await providerClient.client.sendPrompt(sessionID: sessionID, prompt: trimmedPrompt)
            mark(provider: providerClient.configuration.provider, sessionID: sessionID, status: .idle, event: "Idle")
            await refreshSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveSelection(direction: SelectionDirection) {
        guard !sessions.isEmpty else { return }

        let currentIndex = selectedSessionID.flatMap { id in
            sessions.firstIndex { $0.id == id }
        }

        let nextIndex: Int
        switch (direction, currentIndex) {
        case (.up, .some(let index)):
            nextIndex = max(sessions.startIndex, index - 1)
        case (.down, .some(let index)):
            nextIndex = min(sessions.index(before: sessions.endIndex), index + 1)
        case (.up, .none):
            nextIndex = sessions.startIndex
        case (.down, .none):
            nextIndex = sessions.startIndex
        }

        selectedSessionID = sessions[nextIndex].id
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.refreshSessions()
            }
        }
    }

    private static func providerConfigurations() -> [ACPClientConfiguration] {
        var codexEnvironment: [String: String] = [:]
        let codexPath = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: codexPath) {
            codexEnvironment["CODEX_PATH"] = codexPath
        }

        return [
            ACPClientConfiguration(
                provider: .codex,
                executablePaths: [
                    ProcessInfo.processInfo.environment["CODEX_ACP_PATH"],
                    "/opt/homebrew/bin/codex-acp",
                    "/usr/local/bin/codex-acp"
                ].compactMap { $0 },
                environment: codexEnvironment
            ),
            ACPClientConfiguration(
                provider: .claudeCode,
                executablePaths: [
                    ProcessInfo.processInfo.environment["CLAUDE_AGENT_ACP_PATH"],
                    "/opt/homebrew/bin/claude-agent-acp",
                    "/usr/local/bin/claude-agent-acp"
                ].compactMap { $0 }
            ),
            ACPClientConfiguration(
                provider: .goose,
                executablePaths: [
                    ProcessInfo.processInfo.environment["GOOSE_ACP_PATH"],
                    ProcessInfo.processInfo.environment["GOOSE_BINARY"],
                    "/opt/homebrew/lib/node_modules/@aaif/goose/node_modules/@aaif/goose-binary-darwin-arm64/bin/goose",
                    "/opt/homebrew/lib/node_modules/@aaif/goose/node_modules/@aaif/goose-binary-darwin-x64/bin/goose",
                    "/usr/local/lib/node_modules/@aaif/goose/node_modules/@aaif/goose-binary-darwin-arm64/bin/goose",
                    "/usr/local/lib/node_modules/@aaif/goose/node_modules/@aaif/goose-binary-darwin-x64/bin/goose",
                    "/opt/homebrew/bin/goose",
                    "/usr/local/bin/goose"
                ].compactMap { $0 },
                arguments: ["acp"]
            )
        ]
    }

    private func mergeListedSessions(_ listed: [CodexSession]) {
        var byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        for listedSession in listed {
            var session = listedSession
            if let existing = byID[listedSession.id] {
                session.status = existing.status == .working ? .working : .idle
                session.lastEvent = existing.lastEvent
            }
            byID[listedSession.id] = session
        }

        sessions = byID.values.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }

        ensureSelection()
    }

    private func upsert(_ session: CodexSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        ensureSelection()
    }

    private func ensureSelection() {
        guard !sessions.isEmpty else {
            if selectedSessionID != nil {
                selectedSessionID = nil
            }
            return
        }

        if selectedSessionID == nil || !sessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = sessions.first?.id
        }
    }

    private func mark(provider: AgentProvider, sessionID: String, status: SessionStatus, event: String) {
        guard let index = sessions.firstIndex(where: { $0.provider == provider && $0.sessionID == sessionID }) else { return }
        sessions[index].status = status
        sessions[index].lastEvent = event
        sessions[index].updatedAt = Date()
    }

    private func apply(_ event: SessionUpdateEvent) {
        guard let index = sessions.firstIndex(where: { $0.id == event.id }) else { return }
        sessions[index].status = .working
        sessions[index].lastEvent = event.summary
        sessions[index].updatedAt = event.timestamp
    }
}

enum SelectionDirection {
    case up
    case down
}
