import Foundation

@MainActor
public final class SessionStore: ObservableObject {
    @Published var sessions: [CodexSession] = []
    @Published var selectedSessionID: String? {
        didSet {
            pruneSelection()
        }
    }
    @Published var prompt = ""
    @Published var isConnected = false
    @Published var errorMessage: String?

    private let workspaceURL: URL
    private let gooseClient = GooseServeClient()
    private var refreshTask: Task<Void, Never>?
    private var cachedSessionsByID: [String: CodexSession] = [:]
    private var lastActivityBySessionID: [String: Date] = [:]
    private var provisionalTitles = ProvisionalSessionTitles()
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
            let newSession = CodexSession(
                provider: .goose,
                sessionID: sessionID,
                cwd: configuration.cwd,
                title: trimmedPrompt,
                updatedAt: Date(),
                status: .working,
                lastEvent: "Prompt sent"
            )
            provisionalTitles.record(trimmedPrompt, for: newSession.id)
            upsert(newSession)

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

    func mergeListedSessions(_ listed: [CodexSession]) {
        let now = Date()
        var byID: [String: CodexSession] = [:]

        for listedSession in listed {
            var session = listedSession
            if let existing = cachedSessionsByID[listedSession.id] {
                session.lastEvent = existing.lastEvent
                session.title = provisionalTitles.resolvedTitle(for: listedSession)
            }

            if isRecentlyActive(sessionID: listedSession.id, now: now) {
                session.status = .working
            } else {
                session.status = .idle
                lastActivityBySessionID[listedSession.id] = nil
            }

            byID[listedSession.id] = session
        }

        cachedSessionsByID = byID
        expireStaleWorkingSessions(now: now)
        publishVisibleSessions()
    }

    private func upsert(_ session: CodexSession) {
        cachedSessionsByID[session.id] = session

        if session.status == .working {
            lastActivityBySessionID[session.id] = Date()
        } else {
            lastActivityBySessionID[session.id] = nil
        }

        publishVisibleSessions()
    }

    private func pruneSelection() {
        if let selectedSessionID, !sessions.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = nil
        }
    }

    private func mark(provider: AgentProvider, sessionID: String, status: SessionStatus, event: String) {
        let id = "\(provider.rawValue):\(sessionID)"
        guard var session = cachedSessionsByID[id] else { return }
        session.status = status
        session.lastEvent = event
        session.updatedAt = Date()
        cachedSessionsByID[id] = session

        if session.status == .working {
            lastActivityBySessionID[session.id] = Date()
        } else {
            lastActivityBySessionID[session.id] = nil
        }

        publishVisibleSessions()
    }

    private func apply(_ event: SessionUpdateEvent) {
        guard var session = cachedSessionsByID[event.id] else { return }
        session.status = event.status
        session.lastEvent = event.summary
        session.updatedAt = event.timestamp
        cachedSessionsByID[event.id] = session

        if event.status == .working {
            lastActivityBySessionID[event.id] = event.timestamp
        } else {
            lastActivityBySessionID[event.id] = nil
        }

        publishVisibleSessions()
    }

    private func isRecentlyActive(sessionID: String, now: Date) -> Bool {
        guard let lastActivity = lastActivityBySessionID[sessionID] else {
            return false
        }

        return now.timeIntervalSince(lastActivity) < workingStatusTimeout
    }

    private func expireStaleWorkingSessions(now: Date) {
        for id in cachedSessionsByID.keys {
            guard cachedSessionsByID[id]?.status == .working else {
                continue
            }

            guard !isRecentlyActive(sessionID: id, now: now) else {
                continue
            }

            cachedSessionsByID[id]?.status = .idle
            lastActivityBySessionID[id] = nil
        }
    }

    private func publishVisibleSessions() {
        sessions = cachedSessionsByID.values
            .filter { !$0.isArchived }
            .sorted {
                ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
        pruneSelection()
    }
}

enum SelectionDirection {
    case up
    case down
}
