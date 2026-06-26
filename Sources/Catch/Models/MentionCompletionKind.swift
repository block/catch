import SwiftUI

enum MentionCompletionKind: Int, Comparable, Sendable {
    case agent
    case skill

    static func < (lhs: MentionCompletionKind, rhs: MentionCompletionKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .agent: "Agent"
        case .skill: "Skill"
        }
    }

    var symbol: String {
        switch self {
        case .agent: "@"
        case .skill: "/"
        }
    }

    var symbolName: String {
        switch self {
        case .agent: "person.crop.circle"
        case .skill: "book"
        }
    }

    var tint: Color {
        switch self {
        case .agent: .teal
        case .skill: .purple
        }
    }
}
