import Carbon.HIToolbox
import Testing
@testable import CatchKit

@Suite
struct GlobalShortcutTests {
    @Test
    func parsesOptionSpaceWithGooseNormalizedModifierName() throws {
        let shortcut = try #require(GlobalShortcut("alt+space"))

        #expect(shortcut.keyCode == UInt32(kVK_Space))
        #expect(shortcut.modifiers == UInt32(optionKey))
        #expect(shortcut.normalized == "alt+space")
    }

    @Test
    func parsesCommonMacModifierAliases() throws {
        let shortcut = try #require(GlobalShortcut("control+command+option+shift+p"))

        #expect(shortcut.keyCode == UInt32(kVK_ANSI_P))
        #expect(shortcut.modifiers == UInt32(controlKey | cmdKey | optionKey | shiftKey))
        #expect(shortcut.normalized == "ctrl+meta+alt+shift+p")
    }

    @Test
    func parsesPlusKey() throws {
        let shortcut = try #require(GlobalShortcut("meta++"))

        #expect(shortcut.keyCode == UInt32(kVK_ANSI_Equal))
        #expect(shortcut.modifiers == UInt32(cmdKey))
        #expect(shortcut.normalized == "meta+plus")
    }

    @Test
    func rejectsUnmodifiedShortcut() {
        #expect(GlobalShortcut("space") == nil)
    }

    @Test
    func rejectsUnknownKey() {
        #expect(GlobalShortcut("meta+madeup") == nil)
    }

    @Test
    func rejectsModifierOnlyShortcut() {
        #expect(GlobalShortcut("meta") == nil)
    }
}
