import AppKit
import SwiftUI

@MainActor
public final class FloatingWindowController: NSObject {
    private let panelSize = NSSize(width: sessionCreationConceptWidth, height: sessionCreationConceptHeight)
    private let store: SessionStore
    private let isTestBuild: Bool
    private let testWindowMode: TestWindowMode
    private var panel: FloatingPanel?

    public init(
        store: SessionStore,
        isTestBuild: Bool = false,
        testWindowMode: TestWindowMode = .automation
    ) {
        self.store = store
        self.isTestBuild = isTestBuild
        self.testWindowMode = testWindowMode
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideWindowFromNotification),
            name: .hideFloatingWindow,
            object: nil,
        )
    }

    public func showWindow() {
        if panel == nil {
            panel = makePanel()
        }

        guard let panel else { return }

        position(panel)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NotificationCenter.default.post(name: .focusPromptField, object: nil)

        if usesAutomationTestWindowBehavior {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                panel.orderBack(nil)
            }
        }
    }

    func hideWindow() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = isTestBuild ? .normal : .statusBar
        panel.collectionBehavior = collectionBehavior
        panel.title = isTestBuild ? "Catch Test" : "Catch"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: ContentView(isTestBuild: isTestBuild)
                .environmentObject(store)
                .frame(width: panelSize.width, height: panelSize.height)
        )

        return panel
    }

    private var usesAutomationTestWindowBehavior: Bool {
        isTestBuild && testWindowMode == .automation
    }

    private var collectionBehavior: NSWindow.CollectionBehavior {
        if usesAutomationTestWindowBehavior {
            // Agent-driven test windows should stay out of the developer's way:
            // normal level, current Space only, and ordered behind other windows.
            return [.fullScreenAuxiliary, .transient]
        }

        return [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    private func position(_ panel: NSPanel) {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            panel.center()
            return
        }

        let targetX = visibleFrame.midX - (panelSize.width / 2)
        let targetY = visibleFrame.maxY - panelSize.height - 96
        let clampedX = max(visibleFrame.minX + 16, min(targetX, visibleFrame.maxX - panelSize.width - 16))
        let clampedY = max(visibleFrame.minY + 16, targetY)
        panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    @objc private func hideWindowFromNotification() {
        hideWindow()
    }
}

extension FloatingWindowController: NSWindowDelegate {
    public func windowDidBecomeKey(_ notification: Notification) {
        guard store.selectedSessionID == nil else { return }
        NotificationCenter.default.post(name: .focusPromptField, object: nil)
    }
}
