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

struct CodexSession: Identifiable, Equatable {
    let id: String
    var cwd: String
    var title: String
    var updatedAt: Date?
    var status: SessionStatus
    var lastEvent: String

    var displayTitle: String {
        title.isEmpty ? "Untitled session" : title
    }
}

struct SessionUpdateEvent: Equatable {
    let sessionID: String
    let summary: String
    let timestamp: Date
}
