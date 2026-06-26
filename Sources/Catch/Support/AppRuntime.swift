import Foundation

public struct AppRuntime: Sendable {
    public let isTestBuild: Bool
    public let testWindowMode: TestWindowMode
    public let testInstanceID: String?
    public let testBuildLabel: String
    public let isEmbedded: Bool
    public let startsHidden: Bool
    public let globalShortcut: GlobalShortcut?

    public static let current = AppRuntime(
        isTestBuild: ProcessInfo.processInfo.environment["CATCH_TEST_BUILD"] == "1",
        testWindowMode: ProcessInfo.processInfo.arguments.contains("--manual-test-window") ? .manual : .automation,
        arguments: ProcessInfo.processInfo.arguments,
        environment: ProcessInfo.processInfo.environment
    )

    public init(
        isTestBuild: Bool,
        testWindowMode: TestWindowMode,
        arguments: [String],
        environment: [String: String] = [:]
    ) {
        self.isTestBuild = isTestBuild
        self.testWindowMode = testWindowMode
        if isTestBuild {
            testInstanceID = Self.sanitizedTestInstanceID(
                Self.argumentValue(named: "--test-instance-id", in: arguments)
                    ?? environment["CATCH_TEST_INSTANCE_ID"]
            )
        } else {
            testInstanceID = nil
        }
        testBuildLabel = Self.argumentValue(named: "--test-build-label", in: arguments)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "TEST BUILD"
        isEmbedded = arguments.contains("--embedded")
        startsHidden = arguments.contains("--start-hidden")

        let configuredGlobalShortcut = Self.argumentValue(named: "--global-hotkey", in: arguments)
        if isTestBuild, testWindowMode == .automation {
            globalShortcut = nil
        } else if let configured = configuredGlobalShortcut {
            globalShortcut = GlobalShortcut(configured)
        } else if isTestBuild {
            globalShortcut = nil
        } else if isEmbedded {
            globalShortcut = nil
        } else {
            globalShortcut = .defaultStandalone
        }
    }

    public var appName: String {
        guard isTestBuild else { return "Catch" }
        guard let testInstanceID else { return "CatchTest" }
        return "CatchTest-\(testInstanceID)"
    }

    public var registersGlobalShortcut: Bool {
        globalShortcut != nil
    }

    public var appSupportDirectoryName: String {
        appName
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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

    static func sanitizedTestInstanceID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var sanitized = String.UnicodeScalarView()
        var lastWasSeparator = true

        for scalar in trimmed.lowercased().unicodeScalars {
            switch scalar.value {
            case 48...57, 97...122:
                sanitized.append(scalar)
                lastWasSeparator = false
            default:
                if !lastWasSeparator {
                    sanitized.append("-")
                    lastWasSeparator = true
                }
            }
        }

        while sanitized.last?.value == 45 {
            sanitized.removeLast()
        }

        let value = String(sanitized)
        return value.isEmpty ? nil : value
    }
}

public enum TestWindowMode: Sendable {
    case automation
    case manual
}
