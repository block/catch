import Foundation
import Testing

@Suite
struct BuildScriptTests {
    @Test
    func defaultTestModeKeepsSharedCatchTestIdentity() throws {
        let result = try runBuildScript(["--test"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("APP_NAME=CatchTest\n"))
        #expect(result.stdout.contains("BUNDLE_ID=xyz.block.catch.test\n"))
        #expect(result.stdout.contains("/Applications/CatchTest.app\n"))
        #expect(!result.stdout.contains("APP_ARG=--test-instance-id\n"))
    }

    @Test
    func testInstanceArgumentCreatesIsolatedIdentity() throws {
        let result = try runBuildScript(["--test", "--test-instance-id", "Thread 019F/Session Picker"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("APP_NAME=CatchTest-thread-019f-session-picker\n"))
        #expect(result.stdout.contains("BUNDLE_ID=xyz.block.catch.test.thread-019f-session-picker\n"))
        #expect(result.stdout.contains("/Applications/CatchTest-thread-019f-session-picker.app\n"))
        #expect(result.stdout.contains("TEST_INSTANCE_ID=thread-019f-session-picker\n"))
        #expect(result.stdout.contains("APP_ARG=--test-instance-id\n"))
        #expect(result.stdout.contains("APP_ARG=thread-019f-session-picker\n"))
    }

    @Test
    func testInstanceEnvironmentCreatesIsolatedIdentity() throws {
        let result = try runBuildScript(
            ["--test"],
            environment: ["CATCH_TEST_INSTANCE_ID": "E846 Catch"]
        )

        #expect(result.status == 0)
        #expect(result.stdout.contains("APP_NAME=CatchTest-e846-catch\n"))
        #expect(result.stdout.contains("BUNDLE_ID=xyz.block.catch.test.e846-catch\n"))
        #expect(result.stdout.contains("TEST_INSTANCE_ID=e846-catch\n"))
    }

    @Test
    func normalLaunchIgnoresTestInstanceEnvironment() throws {
        let result = try runBuildScript(
            [],
            environment: ["CATCH_TEST_INSTANCE_ID": "E846 Catch"]
        )

        #expect(result.status == 0)
        #expect(result.stdout.contains("APP_NAME=Catch\n"))
        #expect(result.stdout.contains("BUNDLE_ID=xyz.block.catch\n"))
        #expect(result.stdout.contains("APP_BUNDLE=\(NSHomeDirectory())/Applications/Catch.app\n"))
    }

    @Test
    func explicitTestInstanceIsRejectedOutsideTestMode() throws {
        let result = try runBuildScript(["run", "--test-instance-id", "e846"])

        #expect(result.status == 2)
        #expect(result.stderr.contains("--test-instance-id is only valid with --test or --test-manual"))
    }

    @Test
    func manualTestModeRequiresExplicitHotkey() throws {
        let result = try runBuildScript(["--test-manual"])

        #expect(result.status == 2)
        #expect(result.stderr.contains("--test-manual requires CATCH_GLOBAL_HOTKEY"))
    }

    @Test
    func manualTestModePreservesInstanceAndHotkeyArguments() throws {
        let result = try runBuildScript(
            ["--test-manual", "--test-instance-id=e846-catch"],
            environment: [
                "CATCH_GLOBAL_HOTKEY": "cmd+ctrl+c",
                "CATCH_TEST_BUILD_LABEL": "Session Picker (Cmd-Ctrl-C)"
            ]
        )

        #expect(result.status == 0)
        #expect(result.stdout.contains("APP_NAME=CatchTest-e846-catch\n"))
        #expect(result.stdout.contains("APP_ARG=--test-instance-id\n"))
        #expect(result.stdout.contains("APP_ARG=e846-catch\n"))
        #expect(result.stdout.contains("APP_ARG=--manual-test-window\n"))
        #expect(result.stdout.contains("APP_ARG=--test-build-label\n"))
        #expect(result.stdout.contains("APP_ARG=Session Picker (Cmd-Ctrl-C)\n"))
        #expect(result.stdout.contains("APP_ARG=--global-hotkey\n"))
        #expect(result.stdout.contains("APP_ARG=cmd+ctrl+c\n"))
    }

    private func runBuildScript(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [try buildScriptPath()] + arguments

        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment["CATCH_BUILD_AND_RUN_DRY_RUN"] = "1"
        mergedEnvironment.removeValue(forKey: "CATCH_GLOBAL_HOTKEY")
        mergedEnvironment.removeValue(forKey: "CATCH_START_HIDDEN")
        mergedEnvironment.removeValue(forKey: "CATCH_TEST_BUILD_LABEL")
        mergedEnvironment.removeValue(forKey: "CATCH_TEST_INSTANCE_ID")
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func buildScriptPath() throws -> String {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        while true {
            let candidate = directory.appendingPathComponent("script/build_and_run.sh")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                throw ScriptTestError.missingBuildScript
            }
            directory = parent
        }
    }
}

private enum ScriptTestError: Error {
    case missingBuildScript
}
