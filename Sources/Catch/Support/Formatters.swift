import Foundation

enum AppFormatters {
    private enum Strings {
        static var compactAgeNow: String {
            String(
                localized: "session.age.now",
                defaultValue: "now",
                comment: "Compact session timestamp for sessions updated less than one minute ago."
            )
        }
    }

    static func compactAge(for date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else {
            return "-"
        }

        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return Strings.compactAgeNow
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
