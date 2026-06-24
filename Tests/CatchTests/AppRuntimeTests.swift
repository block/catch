import Testing
@testable import CatchKit

@Suite
struct AppRuntimeTests {
    @Test
    func standaloneProductionRegistersGlobalShortcut() {
        let runtime = AppRuntime(isTestBuild: false, testWindowMode: .automation, isEmbedded: false)

        #expect(runtime.registersGlobalShortcut)
    }

    @Test
    func embeddedModeDoesNotRegisterGlobalShortcut() {
        let runtime = AppRuntime(isTestBuild: false, testWindowMode: .automation, isEmbedded: true)

        #expect(!runtime.registersGlobalShortcut)
    }

    @Test
    func testBuildDoesNotRegisterGlobalShortcut() {
        let runtime = AppRuntime(isTestBuild: true, testWindowMode: .automation, isEmbedded: false)

        #expect(!runtime.registersGlobalShortcut)
    }
}
