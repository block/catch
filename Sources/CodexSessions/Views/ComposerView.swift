import AppKit
import SwiftUI

struct ComposerView: View {
    @Binding var prompt: String
    var isFocused: FocusState<Bool>.Binding
    let onMove: (SelectionDirection) -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            PromptTextField(
                text: $prompt,
                placeholder: "New Codex session prompt",
                isFocused: isFocused,
                onMove: onMove,
                onSubmit: onSubmit
            )
            .frame(height: 34)

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.45) : Color.accentColor)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

private struct PromptTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let onMove: (SelectionDirection) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 24, weight: .regular)
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.cell?.sendsActionOnEndEditing = false
        context.coordinator.textField = textField
        context.coordinator.startObservingFocusRequests()
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        guard isFocused.wrappedValue else { return }

        DispatchQueue.main.async {
            context.coordinator.focusTextField()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PromptTextField
        weak var textField: NSTextField?
        private var focusObserver: NSObjectProtocol?

        init(parent: PromptTextField) {
            self.parent = parent
        }

        deinit {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
        }

        func startObservingFocusRequests() {
            guard focusObserver == nil else { return }

            focusObserver = NotificationCenter.default.addObserver(
                forName: .focusPromptField,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.parent.isFocused.wrappedValue = true
                self?.focusTextField()
            }
        }

        func focusTextField() {
            guard let textField, let window = textField.window else { return }

            let isFirstResponder = window.firstResponder === textField || window.firstResponder === textField.currentEditor()
            if !isFirstResponder {
                window.makeFirstResponder(textField)
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused.wrappedValue = false
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }

            if parent.text != textField.stringValue {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(.up)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(.down)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            default:
                return false
            }
        }
    }
}
