import Foundation

struct AppRuntime {
    let isTestBuild: Bool
    let isEmbedded: Bool

    static let current = AppRuntime(
        isTestBuild: ProcessInfo.processInfo.environment["CATCH_TEST_BUILD"] == "1",
        isEmbedded: ProcessInfo.processInfo.arguments.contains("--embedded")
    )

    var appName: String {
        isTestBuild ? "CatchTest" : "Catch"
    }

    var appSupportDirectoryName: String {
        appName
    }
}
