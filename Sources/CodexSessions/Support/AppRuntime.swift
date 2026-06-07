import Foundation

struct AppRuntime {
    let isTestBuild: Bool

    static let current = AppRuntime(
        isTestBuild: ProcessInfo.processInfo.environment["CATCH_TEST_BUILD"] == "1"
    )

    var appName: String {
        isTestBuild ? "CodexSessionsTest" : "CodexSessions"
    }

    var appSupportDirectoryName: String {
        appName
    }
}
