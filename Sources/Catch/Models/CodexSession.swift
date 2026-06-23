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

    var gooseInternalSessionURL: URL? {
        let trimmedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionID.isEmpty,
              let encodedSessionID = trimmedSessionID.addingPercentEncoding(withAllowedCharacters: .urlPathSegmentAllowed)
        else {
            return nil
        }

        return URL(string: "goose-internal://session/\(encodedSessionID)")
    }
}

private extension CharacterSet {
    static let urlPathSegmentAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

struct SessionUpdateEvent: Equatable {
    let provider: AgentProvider
    let sessionID: String
    let status: SessionStatus
    let summary: String
    let timestamp: Date

    var id: String {
        "\(provider.rawValue):\(sessionID)"
    }
}

enum SessionTitleResolver {
    static func title(listedTitle: String, provisionalTitle: String) -> String {
        if isGenericPlaceholderTitle(listedTitle) {
            return provisionalTitle
        }

        return listedTitle
    }

    static func isGenericPlaceholderTitle(_ title: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedTitle.isEmpty || normalizedTitle == "new chat"
    }
}

struct ProvisionalSessionTitles {
    private var titlesBySessionID: [String: String] = [:]

    mutating func record(_ title: String, for sessionID: String) {
        titlesBySessionID[sessionID] = title
    }

    mutating func resolvedTitle(for listedSession: CodexSession) -> String {
        guard let provisionalTitle = titlesBySessionID[listedSession.id] else {
            return listedSession.title
        }

        let resolvedTitle = SessionTitleResolver.title(
            listedTitle: listedSession.title,
            provisionalTitle: provisionalTitle
        )

        if !SessionTitleResolver.isGenericPlaceholderTitle(listedSession.title) {
            titlesBySessionID[listedSession.id] = nil
        }

        return resolvedTitle
    }
}
