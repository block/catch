import AppKit
import SwiftUI

@main
struct CatchApp: App {
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
    private let runtime = AppRuntime.current
    let store: SessionStore
    private var globalShortcutRegistrar: GlobalShortcutRegistrar?
    private lazy var floatingWindowController = FloatingWindowController(store: store, isTestBuild: runtime.isTestBuild)

    override init() {
        store = SessionStore(appSupportDirectoryName: AppRuntime.current.appSupportDirectoryName)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("Catch launched: embedded=\(runtime.isEmbedded) testBuild=\(runtime.isTestBuild)")

        if !runtime.isTestBuild {
            let registrar = GlobalShortcutRegistrar { [weak self] in
                self?.showApp()
            }
            registrar.register()
            globalShortcutRegistrar = registrar
        }

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
    static let focusPromptField = Notification.Name("Catch.focusPromptField")
    static let appWillTerminateProcessClients = Notification.Name("Catch.appWillTerminateProcessClients")
}
