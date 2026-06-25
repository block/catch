import AppKit
import Testing
@testable import CatchKit

@MainActor
@Suite
struct FloatingPanelTests {
    @Test
    func framePlacementPreservesFullyVisibleFrames() {
        let visibleFrame = NSRect(x: 100, y: 100, width: 1200, height: 800)
        let panelFrame = NSRect(x: 250, y: 300, width: 560, height: 430)

        #expect(WindowFramePlacement.isFrameFullyVisible(panelFrame, in: [visibleFrame]))
    }

    @Test
    func framePlacementRejectsPartiallyOffscreenFrames() {
        let visibleFrame = NSRect(x: 100, y: 100, width: 1200, height: 800)
        let panelFrame = NSRect(x: 80, y: 300, width: 560, height: 430)

        #expect(!WindowFramePlacement.isFrameFullyVisible(panelFrame, in: [visibleFrame]))
    }

    @Test
    func framePlacementRejectsFramesSpanningVisibleScreens() {
        let leftScreen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rightScreen = NSRect(x: 1000, y: 0, width: 1000, height: 800)
        let panelFrame = NSRect(x: 900, y: 200, width: 560, height: 430)

        #expect(!WindowFramePlacement.isFrameFullyVisible(panelFrame, in: [leftScreen, rightScreen]))
    }

    @Test
    func defaultPlacementIsClampedInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 100, y: 100, width: 500, height: 350)
        let panelSize = NSSize(width: 560, height: 430)

        let origin = WindowFramePlacement.defaultOrigin(in: visibleFrame, panelSize: panelSize)

        #expect(origin.x == visibleFrame.minX + 16)
        #expect(origin.y == visibleFrame.minY + 16)
    }

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

    @Test
    func shortcutToggleHidesVisibleWindow() {
        let store = SessionStore(appSupportDirectoryName: "CatchTests-\(UUID().uuidString)")
        let controller = FloatingWindowController(store: store, isTestBuild: true, testWindowMode: .manual)
        defer { controller.hideWindow() }

        controller.showWindow()
        #expect(controller.isWindowVisible)

        controller.toggleWindowVisibility()

        #expect(!controller.isWindowVisible)
    }
}

private final class MenuActionTarget: NSObject {
    var didPerformClose = false

    @objc func performClose(_ sender: Any?) {
        didPerformClose = true
    }
}
