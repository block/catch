import AppKit
import SwiftUI

@main
struct CodexSessionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup("Codex Sessions", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(width: 560, height: 430)
                .background(WindowConfigurator())
                .task {
                    await store.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Session") {
                Button("Refresh Sessions") {
                    Task { await store.refreshSessions() }
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalShortcutRegistrar: GlobalShortcutRegistrar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        let registrar = GlobalShortcutRegistrar {
            Self.showApp()
        }
        registrar.register()
        globalShortcutRegistrar = registrar
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcutRegistrar?.unregister()
        NotificationCenter.default.post(name: .appWillTerminateProcessClients, object: nil)
    }

    private static func showApp() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NSApp.windows.first?.orderFrontRegardless()
        NotificationCenter.default.post(name: .focusPromptField, object: nil)
    }
}

extension Notification.Name {
    static let focusPromptField = Notification.Name("CodexSessions.focusPromptField")
    static let appWillTerminateProcessClients = Notification.Name("CodexSessions.appWillTerminateProcessClients")
}
