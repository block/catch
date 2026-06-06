import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [CodexSession] = []
    @Published var selectedSessionID: String?
    @Published var prompt = ""
    @Published var isConnected = false
    @Published var errorMessage: String?

    private let workspaceURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("CodexSessions/Workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private var client: ACPClient?
    private var refreshTask: Task<Void, Never>?

    var selectedSession: CodexSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    func start() async {
        guard client == nil else { return }

        let client = ACPClient(cwd: workspaceURL)
        self.client = client

        do {
            try client.start { [weak self] event in
                Task { @MainActor in
                    self?.apply(event)
                }
            }
            try await client.initialize()
            isConnected = true
            await refreshSessions()
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
        }

        NotificationCenter.default.addObserver(forName: .appWillTerminateProcessClients, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.client?.stop()
            }
        }
    }

    func refreshSessions() async {
        guard let client else { return }

        do {
            let response = try await client.listSessions()
            mergeListedSessions(response.sessions)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitPrompt() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, let client else { return }

        prompt = ""
        errorMessage = nil

        do {
            let sessionID = try await client.createSession()
            upsert(
                CodexSession(
                    id: sessionID,
                    cwd: workspaceURL.path,
                    title: String(trimmedPrompt.prefix(80)),
                    updatedAt: Date(),
                    status: .working,
                    lastEvent: "Prompt sent"
                )
            )

            try await client.sendPrompt(sessionID: sessionID, prompt: trimmedPrompt)
            mark(sessionID: sessionID, status: .idle, event: "Idle")
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

        if selectedSessionID == nil || !sessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = sessions.first?.id
        }
    }

    private func upsert(_ session: CodexSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    private func mark(sessionID: String, status: SessionStatus, event: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].status = status
        sessions[index].lastEvent = event
        sessions[index].updatedAt = Date()
    }

    private func apply(_ event: SessionUpdateEvent) {
        guard let index = sessions.firstIndex(where: { $0.id == event.sessionID }) else { return }
        sessions[index].status = .working
        sessions[index].lastEvent = event.summary
        sessions[index].updatedAt = event.timestamp
    }
}

enum SelectionDirection {
    case up
    case down
}
