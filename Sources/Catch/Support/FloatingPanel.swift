import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // This accessory NSPanel has no ordinary SwiftUI window scene, so route
        // key equivalents through the app menu to invoke standard commands.
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
