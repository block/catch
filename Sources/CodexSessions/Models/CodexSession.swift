import Foundation

enum SessionStatus: String, CaseIterable, Identifiable {
    case idle
    case working
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .working:
            return "Working"
        case .unknown:
            return "Unknown"
        }
    }
}

enum AgentProvider: String, CaseIterable, Identifiable {
    case codex
    case claudeCode
    case goose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .goose:
            return "Goose"
        }
    }

    var badge: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude"
        case .goose:
            return "Goose"
        }
    }
}

struct CodexSession: Identifiable, Equatable {
    var provider: AgentProvider
    var sessionID: String
    var cwd: String
    var title: String
    var updatedAt: Date?
    var status: SessionStatus
    var lastEvent: String

    var id: String {
        "\(provider.rawValue):\(sessionID)"
    }

    var displayTitle: String {
        title.isEmpty ? "Untitled session" : title
    }
}

struct SessionUpdateEvent: Equatable {
    let provider: AgentProvider
    let sessionID: String
    let summary: String
    let timestamp: Date

    var id: String {
        "\(provider.rawValue):\(sessionID)"
    }
}
