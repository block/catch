import Foundation

@MainActor
public final class SessionStore: ObservableObject {
    @Published var sessions: [CodexSession] = []
    @Published var selectedSessionID: String? {
        didSet {
            ensureSelection()
        }
    }
    @Published var prompt = ""
    @Published var isConnected = false
    @Published var errorMessage: String?

    private let workspaceURL: URL
    private let gooseClient = GooseServeClient()
    private var refreshTask: Task<Void, Never>?
    private var lastActivityBySessionID: [String: Date] = [:]
    private let workingStatusTimeout: TimeInterval = 60

    public init(appSupportDirectoryName: String = "Catch") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("\(appSupportDirectoryName)/Workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        workspaceURL = url
    }

    var selectedSession: CodexSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    public func start() async {
        guard !isConnected else { return }

        do {
            try await gooseClient.start { [weak self] event in
                Task { @MainActor in
                    self?.apply(event)
                }
            }
            try await gooseClient.initialize()
            isConnected = true
            errorMessage = nil
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
            return
        }

        await refreshSessions()
        startPolling()

        NotificationCenter.default.addObserver(forName: .appWillTerminateProcessClients, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.gooseClient.stop()
            }
        }
    }

    public func refreshSessions() async {
        guard isConnected else { return }

        do {
            let listed = try await gooseClient.listSessions()
            mergeListedSessions(listed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSessionCreationMetadata() async throws -> GooseSessionCreationMetadata {
        try await gooseClient.loadSessionCreationMetadata()
    }

    func submitPrompt(configuration: GooseSessionConfiguration) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, isConnected else { return }

        prompt = ""
        errorMessage = nil

        do {
            let sessionID = try await gooseClient.createSession(configuration: configuration)
            upsert(
                CodexSession(
                    provider: .goose,
                    sessionID: sessionID,
                    cwd: configuration.cwd,
                    title: String(trimmedPrompt.prefix(80)),
                    updatedAt: Date(),
                    status: .working,
                    lastEvent: "Prompt sent"
                )
            )

            try await gooseClient.sendPrompt(sessionID: sessionID, prompt: trimmedPrompt)
            mark(provider: .goose, sessionID: sessionID, status: .idle, event: "Idle")
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
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.refreshSessions()
            }
        }
    }

    private func mergeListedSessions(_ listed: [CodexSession]) {
        let now = Date()
        var byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        for listedSession in listed {
            var session = listedSession
            if let existing = byID[listedSession.id] {
                session.lastEvent = existing.lastEvent
            }

            if isRecentlyActive(sessionID: listedSession.id, now: now) {
                session.status = .working
            } else {
                session.status = .idle
                lastActivityBySessionID[listedSession.id] = nil
            }

            byID[listedSession.id] = session
        }

        sessions = byID.values.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
        expireStaleWorkingSessions(now: now)

        ensureSelection()
    }

    private func upsert(_ session: CodexSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }

        if session.status == .working {
            lastActivityBySessionID[session.id] = Date()
        } else {
            lastActivityBySessionID[session.id] = nil
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

        if status == .working {
            lastActivityBySessionID[sessions[index].id] = Date()
        } else {
            lastActivityBySessionID[sessions[index].id] = nil
        }
    }

    private func apply(_ event: SessionUpdateEvent) {
        guard let index = sessions.firstIndex(where: { $0.id == event.id }) else { return }
        sessions[index].status = event.status
        sessions[index].lastEvent = event.summary
        sessions[index].updatedAt = event.timestamp

        if event.status == .working {
            lastActivityBySessionID[event.id] = event.timestamp
        } else {
            lastActivityBySessionID[event.id] = nil
        }
    }

    private func isRecentlyActive(sessionID: String, now: Date) -> Bool {
        guard let lastActivity = lastActivityBySessionID[sessionID] else {
            return false
        }

        return now.timeIntervalSince(lastActivity) < workingStatusTimeout
    }

    private func expireStaleWorkingSessions(now: Date) {
        for index in sessions.indices where sessions[index].status == .working {
            guard !isRecentlyActive(sessionID: sessions[index].id, now: now) else {
                continue
            }

            sessions[index].status = .idle
            lastActivityBySessionID[sessions[index].id] = nil
        }
    }
}

enum SelectionDirection {
    case up
    case down
}
