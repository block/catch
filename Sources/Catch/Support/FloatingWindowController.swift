import AppKit
import SwiftUI

@MainActor
public final class FloatingWindowController: NSObject {
    private let panelSize = NSSize(width: 560, height: 430)
    private let store: SessionStore
    private let isTestBuild: Bool
    private var panel: FloatingPanel?

    public init(store: SessionStore, isTestBuild: Bool = false) {
        self.store = store
        self.isTestBuild = isTestBuild
        super.init()
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

        if isTestBuild {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                panel.orderBack(nil)
            }
        }
    }

    func hideWindow() {
        panel?.orderOut(nil)
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
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
}

extension FloatingWindowController: NSWindowDelegate {
    public func windowDidResignKey(_ notification: Notification) {
        NotificationCenter.default.post(name: .focusPromptField, object: nil)
    }
}
