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
            CommandGroup(replacing: .newItem) {}
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
        installCommandMenu()
        DispatchQueue.main.async { [weak self] in
            self?.installCommandMenu()
        }

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

    func hideFloatingWindow() {
        NotificationCenter.default.post(name: .hideFloatingWindow, object: nil)
    }

    // SwiftUI `Commands` do not reliably dispatch standard menu actions for this
    // accessory, Settings-scene-only app. Install a small AppKit menu so system
    // Hide and Close Window actions route through the same hide path as Escape.
    private func installCommandMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = makeAppMenu()

        let sessionMenuItem = NSMenuItem()
        mainMenu.addItem(sessionMenuItem)
        sessionMenuItem.submenu = makeSessionMenu()

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        windowMenuItem.submenu = makeWindowMenu()

        NSApp.mainMenu = mainMenu
    }

    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu(title: "Catch")
        menu.addItem(menuItem(title: "Hide Catch", action: #selector(hide(_:)), keyEquivalent: "h"))
        menu.addItem(menuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifierMask: [.command, .option],
            target: NSApp
        ))
        menu.addItem(menuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Catch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", target: NSApp))
        return menu
    }

    private func makeSessionMenu() -> NSMenu {
        let menu = NSMenu(title: "Session")
        menu.addItem(menuItem(title: "Refresh Sessions", action: #selector(refreshSessions(_:)), keyEquivalent: "r"))
        menu.addItem(menuItem(title: "Focus Prompt", action: #selector(focusPrompt(_:)), keyEquivalent: "l"))
        return menu
    }

    private func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(menuItem(title: "Close Window", action: #selector(performClose(_:)), keyEquivalent: "w"))
        return menu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        item.target = target ?? self
        return item
    }

    @objc func hide(_ sender: Any?) {
        hideFloatingWindow()
    }

    @objc func performClose(_ sender: Any?) {
        hideFloatingWindow()
    }

    @objc private func refreshSessions(_ sender: Any?) {
        Task { await store.refreshSessions() }
    }

    @objc private func focusPrompt(_ sender: Any?) {
        NotificationCenter.default.post(name: .focusPromptField, object: nil)
    }

    private func showApp() {
        floatingWindowController.showWindow()
    }
}
