import Foundation

enum ReasoningEffort: String, CaseIterable, Identifiable {
    case off
    case low
    case medium
    case high
    case max

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Max"
        }
    }

    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Max"
        }
    }

    var acpValue: String? {
        rawValue
    }
}
