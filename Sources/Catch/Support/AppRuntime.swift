import Foundation

public struct AppRuntime: Sendable {
    public let isTestBuild: Bool
    public let testWindowMode: TestWindowMode
    public let isEmbedded: Bool

    public static let current = AppRuntime(
        isTestBuild: ProcessInfo.processInfo.environment["CATCH_TEST_BUILD"] == "1",
        testWindowMode: ProcessInfo.processInfo.arguments.contains("--manual-test-window") ? .manual : .automation,
        isEmbedded: ProcessInfo.processInfo.arguments.contains("--embedded")
    )

    public var appName: String {
        isTestBuild ? "CatchTest" : "Catch"
    }

    public var appSupportDirectoryName: String {
        appName
    }
}

public enum TestWindowMode: Sendable {
    case automation
    case manual
}
