import AppKit
import Testing
@testable import CatchKit

@MainActor
@Suite
struct FloatingPanelTests {
    @Test
    func keyEquivalentsRouteThroughAppMenu() throws {
        let target = MenuActionTarget()
        let menu = NSMenu()
        let item = NSMenuItem(title: "Close Window", action: #selector(MenuActionTarget.performClose(_:)), keyEquivalent: "w")
        item.keyEquivalentModifierMask = [.command]
        item.target = target
        menu.addItem(item)

        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        app.mainMenu = menu
        defer {
            app.mainMenu = previousMenu
        }

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        #expect(panel.performKeyEquivalent(with: event))
        #expect(target.didPerformClose)
    }
}

private final class MenuActionTarget: NSObject {
    var didPerformClose = false

    @objc func performClose(_ sender: Any?) {
        didPerformClose = true
    }
}
