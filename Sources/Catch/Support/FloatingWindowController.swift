import AppKit
import SwiftUI

@MainActor
public final class FloatingWindowController: NSObject {
    private let panelSize = NSSize(width: sessionCreationConceptWidth, height: sessionCreationConceptHeight)
    private let store: SessionStore
    private let isTestBuild: Bool
    private let testWindowMode: TestWindowMode
    private let testBuildLabel: String
    private var panel: FloatingPanel?
    private var hasPositionedPanel = false
    private var isHidingWindow = false

    public init(
        store: SessionStore,
        isTestBuild: Bool = false,
        testWindowMode: TestWindowMode = .automation,
        testBuildLabel: String = "TEST BUILD"
    ) {
        self.store = store
        self.isTestBuild = isTestBuild
        self.testWindowMode = testWindowMode
        self.testBuildLabel = testBuildLabel
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideWindowFromNotification),
            name: .hideFloatingWindow,
            object: nil,
        )

        if !isTestBuild {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidResignActive),
                name: NSApplication.didResignActiveNotification,
                object: nil,
            )
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(workspaceDidActivateApplication),
                name: NSWorkspace.didActivateApplicationNotification,
                object: nil
            )
        }
    }

    public func showWindow() {
        if panel == nil {
            panel = makePanel()
        }

        guard let panel else { return }

        positionForDisplayIfNeeded(panel)
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
        isHidingWindow = true
        panel.orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            self?.isHidingWindow = false
        }
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
            rootView: ContentView(isTestBuild: isTestBuild, testBuildLabel: testBuildLabel)
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

    private func positionForDisplayIfNeeded(_ panel: NSPanel) {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        guard !visibleFrames.isEmpty else {
            if !hasPositionedPanel {
                panel.center()
                hasPositionedPanel = true
            }
            return
        }

        // NSPanel preserves its frame across orderOut/orderFront. Keep that
        // user-chosen frame unless the current display layout can no longer
        // show the whole panel.
        if hasPositionedPanel, WindowFramePlacement.isFrameFullyVisible(panel.frame, in: visibleFrames) {
            return
        }

        let visibleFrame = NSScreen.main?.visibleFrame ?? visibleFrames[0]
        panel.setFrameOrigin(WindowFramePlacement.defaultOrigin(in: visibleFrame, panelSize: panelSize))
        hasPositionedPanel = true
    }

    @objc private func hideWindowFromNotification() {
        hideWindow()
    }

    @objc private func appDidResignActive() {
        hideWindow()
    }

    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              activatedApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }

        hideWindow()
    }
}

extension FloatingWindowController: NSWindowDelegate {
    public func windowDidBecomeKey(_ notification: Notification) {
        guard store.selectedSessionID == nil else { return }
        NotificationCenter.default.post(name: .focusPromptField, object: nil)
    }

    public func windowDidResignKey(_ notification: Notification) {
        guard !isHidingWindow, !isTestBuild else { return }

        Task { @MainActor [weak self] in
            guard let self, let panel, panel.isVisible, !panel.isKeyWindow else { return }
            hideWindow()
        }
    }
}

enum WindowFramePlacement {
    static func isFrameFullyVisible(_ frame: NSRect, in visibleFrames: [NSRect]) -> Bool {
        visibleFrames.contains { visibleFrame in
            visibleFrame.contains(frame)
        }
    }

    static func defaultOrigin(in visibleFrame: NSRect, panelSize: NSSize) -> NSPoint {
        let targetX = visibleFrame.midX - (panelSize.width / 2)
        let targetY = visibleFrame.maxY - panelSize.height - 96
        let clampedX = max(visibleFrame.minX + 16, min(targetX, visibleFrame.maxX - panelSize.width - 16))
        let clampedY = max(visibleFrame.minY + 16, targetY)
        return NSPoint(x: clampedX, y: clampedY)
    }
}
