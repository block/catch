import Foundation
import Testing
@testable import CatchKit

@Suite
struct GooseProjectOptionTests {
    @Test
    func projectSourceUsesFirstNonEmptyWorkingDirectoryAsCWD() {
        let source = GooseSourceEntry(
            type: "project",
            name: "sample-project",
            description: "A project",
            content: "",
            path: "/Users/test/.config/goose/projects/sample-project.md",
            global: true,
            writable: true,
            title: "Sample Project",
            color: "#0055ff",
            workingDirs: ["  ", "/Users/test/Development/sample", "/Users/test/other"]
        )

        let option = GooseProjectOption(source: source)

        #expect(option.id == "sample-project")
        #expect(option.title == "Sample Project")
        #expect(option.cwd == "/Users/test/Development/sample")
        #expect(option.projectID == "sample-project")
    }

    @Test
    func pathlessProjectSourceFallsBackToArtifactDirectory() {
        let source = GooseSourceEntry(
            type: "project",
            name: "pathless-project",
            description: "",
            content: "",
            path: "/Users/test/.config/goose/projects/pathless-project.md",
            global: true,
            writable: true,
            title: nil,
            color: nil,
            workingDirs: []
        )

        let option = GooseProjectOption(source: source)

        #expect(option.title == "pathless-project")
        #expect(option.cwd == NSHomeDirectory() + "/goose artifacts")
        #expect(option.projectID == "pathless-project")
    }
}
