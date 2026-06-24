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
}
