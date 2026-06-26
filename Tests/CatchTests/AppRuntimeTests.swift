import Testing
@testable import CatchKit

@Suite
struct AppRuntimeTests {
    @Test
    func standaloneProductionRegistersGlobalShortcut() {
        let runtime = AppRuntime(isTestBuild: false, testWindowMode: .automation, arguments: ["Catch"])

        #expect(runtime.registersGlobalShortcut)
        #expect(runtime.globalShortcut == GlobalShortcut("alt+space"))
    }

    @Test
    func embeddedModeWithoutConfiguredHotkeyDoesNotRegisterGlobalShortcut() {
        let runtime = AppRuntime(isTestBuild: false, testWindowMode: .automation, arguments: ["Catch", "--embedded"])

        #expect(!runtime.registersGlobalShortcut)
        #expect(runtime.globalShortcut == nil)
        #expect(!runtime.startsHidden)
    }

    @Test
    func startHiddenArgumentStartsHidden() {
        let runtime = AppRuntime(
            isTestBuild: false,
            testWindowMode: .automation,
            arguments: ["Catch", "--embedded", "--global-hotkey", "alt+space", "--start-hidden"]
        )

        #expect(runtime.startsHidden)
        #expect(runtime.globalShortcut == GlobalShortcut("alt+space"))
    }

    @Test
    func embeddedModeWithConfiguredHotkeyRegistersGlobalShortcut() {
        let runtime = AppRuntime(
            isTestBuild: false,
            testWindowMode: .automation,
            arguments: ["Catch", "--embedded", "--global-hotkey", "meta+shift+p"]
        )

        #expect(runtime.registersGlobalShortcut)
        #expect(runtime.globalShortcut == GlobalShortcut("meta+shift+p"))
    }

    @Test
    func embeddedModeAcceptsEqualsFormConfiguredHotkey() {
        let runtime = AppRuntime(
            isTestBuild: false,
            testWindowMode: .automation,
            arguments: ["Catch", "--embedded", "--global-hotkey=ctrl+alt+c"]
        )

        #expect(runtime.globalShortcut == GlobalShortcut("ctrl+alt+c"))
    }

    @Test
    func embeddedModeWithInvalidConfiguredHotkeyDoesNotRegisterGlobalShortcut() {
        let runtime = AppRuntime(
            isTestBuild: false,
            testWindowMode: .automation,
            arguments: ["Catch", "--embedded", "--global-hotkey", "space"]
        )

        #expect(!runtime.registersGlobalShortcut)
        #expect(runtime.globalShortcut == nil)
    }

    @Test
    func testBuildDoesNotRegisterGlobalShortcut() {
        let runtime = AppRuntime(
            isTestBuild: true,
            testWindowMode: .automation,
            arguments: ["Catch", "--global-hotkey", "meta+shift+p"]
        )

        #expect(!runtime.registersGlobalShortcut)
        #expect(runtime.globalShortcut == nil)
    }

    @Test
    func testBuildWithoutInstanceUsesSharedTestIdentity() {
        let runtime = AppRuntime(isTestBuild: true, testWindowMode: .automation, arguments: ["Catch"])

        #expect(runtime.testInstanceID == nil)
        #expect(runtime.appName == "CatchTest")
        #expect(runtime.appSupportDirectoryName == "CatchTest")
    }

    @Test
    func testBuildInstanceArgumentUsesIsolatedIdentity() {
        let runtime = AppRuntime(
            isTestBuild: true,
            testWindowMode: .automation,
            arguments: ["Catch", "--test-instance-id", "Thread 019F/Session Picker"]
        )

        #expect(runtime.testInstanceID == "thread-019f-session-picker")
        #expect(runtime.appName == "CatchTest-thread-019f-session-picker")
        #expect(runtime.appSupportDirectoryName == "CatchTest-thread-019f-session-picker")
    }

    @Test
    func testBuildInstanceAcceptsEqualsArgumentValue() {
        let runtime = AppRuntime(
            isTestBuild: true,
            testWindowMode: .automation,
            arguments: ["Catch", "--test-instance-id=E846 Catch"]
        )

        #expect(runtime.testInstanceID == "e846-catch")
        #expect(runtime.appSupportDirectoryName == "CatchTest-e846-catch")
    }

    @Test
    func testBuildInstanceFallsBackToEnvironment() {
        let runtime = AppRuntime(
            isTestBuild: true,
            testWindowMode: .automation,
            arguments: ["Catch"],
            environment: ["CATCH_TEST_INSTANCE_ID": "Env Instance"]
        )

        #expect(runtime.testInstanceID == "env-instance")
        #expect(runtime.appSupportDirectoryName == "CatchTest-env-instance")
    }

    @Test
    func productionIgnoresTestInstanceEnvironment() {
        let runtime = AppRuntime(
            isTestBuild: false,
            testWindowMode: .automation,
            arguments: ["Catch"],
            environment: ["CATCH_TEST_INSTANCE_ID": "Env Instance"]
        )

        #expect(runtime.testInstanceID == nil)
        #expect(runtime.appName == "Catch")
        #expect(runtime.appSupportDirectoryName == "Catch")
    }

    @Test
    func testBuildRegistersExplicitGlobalShortcut() {
        let runtime = AppRuntime(
            isTestBuild: true,
            testWindowMode: .manual,
            arguments: ["Catch", "--global-hotkey", "cmd+ctrl+c"]
        )

        #expect(runtime.registersGlobalShortcut)
        #expect(runtime.globalShortcut == GlobalShortcut("cmd+ctrl+c"))
    }

    @Test
    func testBuildLabelDefaultsToTestBuild() {
        let runtime = AppRuntime(isTestBuild: true, testWindowMode: .automation, arguments: ["Catch"])

        #expect(runtime.testBuildLabel == "TEST BUILD")
    }

    @Test
    func testBuildLabelAcceptsArgumentValue() {
        let runtime = AppRuntime(
            isTestBuild: true,
            testWindowMode: .automation,
            arguments: ["Catch", "--test-build-label", "Shortcut QA"]
        )

        #expect(runtime.testBuildLabel == "Shortcut QA")
    }

    @Test
    func testBuildLabelAcceptsEqualsArgumentValue() {
        let runtime = AppRuntime(
            isTestBuild: true,
            testWindowMode: .automation,
            arguments: ["Catch", "--test-build-label=Session Picker"]
        )

        #expect(runtime.testBuildLabel == "Session Picker")
    }

    @Test
    func blankTestBuildLabelFallsBackToDefault() {
        let runtime = AppRuntime(
            isTestBuild: true,
            testWindowMode: .automation,
            arguments: ["Catch", "--test-build-label", "  "]
        )

        #expect(runtime.testBuildLabel == "TEST BUILD")
    }
}
