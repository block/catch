import AppKit
import SwiftUI

struct KeyboardMonitor: NSViewRepresentable {
    let onMove: (SelectionDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove)
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
        private var monitor: Any?

        init(onMove: @escaping (SelectionDirection) -> Void) {
            self.onMove = onMove
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
