import Foundation

enum AppFormatters {
    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func updatedText(for date: Date?) -> String {
        guard let date else {
            return "No update time"
        }

        let now = Date()
        if date >= now || now.timeIntervalSince(date) < 1 {
            return "Just now"
        }

        return relativeDate.localizedString(for: date, relativeTo: now)
    }

    static func compactAge(for date: Date?) -> String {
        guard let date else {
            return "-"
        }

        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "\(max(1, seconds))s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        let days = hours / 24
        return "\(days)d"
    }
}
