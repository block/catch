import AppKit
import CatchKit
import SwiftUI

@main
struct CatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            TextEditingCommands()
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .pasteboard) {
                Button("Paste and Match Style") {
                    NSApp.sendAction(#selector(NSTextView.pasteAsPlainText(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .option, .shift])
            }
            CommandGroup(replacing: .appVisibility) {
                Button("Hide Catch") {
                    appDelegate.hideFloatingWindow()
                }
                .keyboardShortcut("h")

                Button("Hide Others") {
                    NSApp.hideOtherApplications(nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button("Show All") {
                    NSApp.unhideAllApplications(nil)
                }
            }
            CommandMenu("Session") {
                Button("Refresh Sessions") {
                    appDelegate.refreshSessions()
                }
                .keyboardShortcut("r")

                Button("Focus Prompt") {
                    appDelegate.focusPrompt()
                }
                .keyboardShortcut("l")
            }
            CommandGroup(replacing: .windowSize) {
                Button("Close Window") {
                    appDelegate.hideFloatingWindow()
                }
                .keyboardShortcut("w")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.current
    let store: SessionStore
    private var globalShortcutRegistrar: GlobalShortcutRegistrar?
    private lazy var floatingWindowController = FloatingWindowController(
        store: store,
        isTestBuild: runtime.isTestBuild,
        testWindowMode: runtime.testWindowMode,
        testBuildLabel: runtime.testBuildLabel
    )

    override init() {
        store = SessionStore(
            appSupportDirectoryName: AppRuntime.current.appSupportDirectoryName,
            runtime: AppRuntime.current
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let shortcut = runtime.globalShortcut {
            let registrar = GlobalShortcutRegistrar(shortcut: shortcut) { [weak self] in
                self?.floatingWindowController.toggleWindowVisibility()
            }
            registrar.register()
            globalShortcutRegistrar = registrar
        }

        Task {
            await store.start()
        }
        if !runtime.startsHidden {
            floatingWindowController.showWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcutRegistrar?.unregister()
        NotificationCenter.default.post(name: .appWillTerminateProcessClients, object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showApp()
        return false
    }

    func hideFloatingWindow() {
        NotificationCenter.default.post(name: .hideFloatingWindow, object: nil)
    }

    func refreshSessions() {
        Task { await store.refreshSessions() }
    }

    func focusPrompt() {
        NotificationCenter.default.post(name: .focusPromptField, object: nil)
    }

    private func showApp() {
        floatingWindowController.showWindow()
    }
}
