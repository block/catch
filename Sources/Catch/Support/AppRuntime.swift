import Foundation

public struct AppRuntime: Sendable {
    public let isTestBuild: Bool
    public let testWindowMode: TestWindowMode
    public let isEmbedded: Bool
    public let globalShortcut: GlobalShortcut?

    public static let current = AppRuntime(
        isTestBuild: ProcessInfo.processInfo.environment["CATCH_TEST_BUILD"] == "1",
        testWindowMode: ProcessInfo.processInfo.arguments.contains("--manual-test-window") ? .manual : .automation,
        arguments: ProcessInfo.processInfo.arguments
    )

    public init(isTestBuild: Bool, testWindowMode: TestWindowMode, arguments: [String]) {
        self.isTestBuild = isTestBuild
        self.testWindowMode = testWindowMode
        isEmbedded = arguments.contains("--embedded")

        if isTestBuild {
            globalShortcut = nil
        } else if let configured = Self.argumentValue(named: "--global-hotkey", in: arguments) {
            globalShortcut = GlobalShortcut(configured)
        } else if isEmbedded {
            globalShortcut = nil
        } else {
            globalShortcut = .defaultStandalone
        }
    }

    public var appName: String {
        isTestBuild ? "CatchTest" : "Catch"
    }

    public var registersGlobalShortcut: Bool {
        globalShortcut != nil
    }

    public var appSupportDirectoryName: String {
        appName
    }
}

private extension AppRuntime {
    static func argumentValue(named name: String, in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == name {
                let nextIndex = arguments.index(after: index)
                guard arguments.indices.contains(nextIndex) else { return nil }
                return arguments[nextIndex]
            }

            let prefix = "\(name)="
            if argument.hasPrefix(prefix) {
                return String(argument.dropFirst(prefix.count))
            }
        }
        return nil
    }
}

public enum TestWindowMode: Sendable {
    case automation
    case manual
}
