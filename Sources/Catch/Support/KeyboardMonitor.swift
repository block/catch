import AppKit
import SwiftUI

struct KeyboardMonitor: NSViewRepresentable {
    let onMove: (SelectionDirection) -> Bool
    var onAccept: (KeyboardAcceptKey) -> Bool = { _ in false }
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove, onAccept: onAccept, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMove = onMove
        context.coordinator.onAccept = onAccept
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onMove: (SelectionDirection) -> Bool
        var onAccept: (KeyboardAcceptKey) -> Bool
        var onEscape: () -> Void
        private var monitor: Any?

        init(
            onMove: @escaping (SelectionDirection) -> Bool,
            onAccept: @escaping (KeyboardAcceptKey) -> Bool,
            onEscape: @escaping () -> Void
        ) {
            self.onMove = onMove
            self.onAccept = onAccept
            self.onEscape = onEscape
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let activeModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                guard activeModifiers.isEmpty else {
                    return event
                }

                switch event.keyCode {
                case 126:
                    if self?.onMove(.up) == true {
                        return nil
                    }
                    return event
                case 125:
                    if self?.onMove(.down) == true {
                        return nil
                    }
                    return event
                case 36:
                    if self?.onAccept(.returnKey) == true {
                        return nil
                    }
                    return event
                case 48:
                    if self?.onAccept(.tab) == true {
                        return nil
                    }
                    return event
                case 53:
                    self?.onEscape()
                    return nil
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

enum KeyboardAcceptKey {
    case returnKey
    case tab
}
