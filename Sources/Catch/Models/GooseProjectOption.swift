import Foundation
import SwiftUI

struct GooseProjectOption: Identifiable, Equatable, Comparable, Sendable {
    let id: String
    let title: String
    let cwd: String
    let projectID: String?
    let tint: Color

    static let none = GooseProjectOption(
        id: "none",
        title: "No project",
        cwd: NSHomeDirectory(),
        projectID: nil,
        tint: .secondary.opacity(0.4)
    )

    init(id: String, title: String, cwd: String, projectID: String?, tint: Color) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.projectID = projectID
        self.tint = tint
    }

    init(source: GooseSourceEntry) {
        let displayTitle = source.title ?? source.name
        self.init(
            id: source.name,
            title: displayTitle,
            cwd: Self.defaultCWD(for: source),
            projectID: source.name,
            tint: source.color.flatMap(Color.init(hex:)) ?? .purple
        )
    }

    static func < (lhs: GooseProjectOption, rhs: GooseProjectOption) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func defaultCWD(for source: GooseSourceEntry) -> String {
        // `source.path` is the project definition file; Goose2 uses the first
        // project working dir as cwd.
        if let projectWorkingDir = source.workingDirs
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        {
            return projectWorkingDir
        }

        return NSHomeDirectory() + "/goose artifacts"
    }
}
