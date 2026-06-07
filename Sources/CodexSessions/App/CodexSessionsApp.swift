import AppKit
import SwiftUI

@main
struct CodexSessionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Session") {
                Button("Refresh Sessions") {
                    Task { await appDelegate.store.refreshSessions() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Focus Prompt") {
                    NotificationCenter.default.post(name: .focusPromptField, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    private var globalShortcutRegistrar: GlobalShortcutRegistrar?
    private lazy var floatingWindowController = FloatingWindowController(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let registrar = GlobalShortcutRegistrar { [weak self] in
            self?.showApp()
        }
        registrar.register()
        globalShortcutRegistrar = registrar

        Task {
            await store.start()
        }
        floatingWindowController.showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcutRegistrar?.unregister()
        NotificationCenter.default.post(name: .appWillTerminateProcessClients, object: nil)
    }

    private func showApp() {
        floatingWindowController.showWindow()
    }
}

extension Notification.Name {
    static let focusPromptField = Notification.Name("CodexSessions.focusPromptField")
    static let appWillTerminateProcessClients = Notification.Name("CodexSessions.appWillTerminateProcessClients")
}
