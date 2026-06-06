import AppKit
import SwiftUI

struct KeyboardMonitor: NSViewRepresentable {
    let onMove: (SelectionDirection) -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private let onMove: (SelectionDirection) -> Void
        private let onEscape: () -> Void
        private var monitor: Any?

        init(onMove: @escaping (SelectionDirection) -> Void, onEscape: @escaping () -> Void) {
            self.onMove = onMove
            self.onEscape = onEscape
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
                    return event
                }

                switch event.keyCode {
                case 126:
                    self?.onMove(.up)
                    return nil
                case 125:
                    self?.onMove(.down)
                    return nil
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
