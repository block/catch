import AppKit

final class PromptNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onFocusIntent: (() -> Void)?
    var onMove: ((SelectionDirection, PromptMoveContext) -> Bool)?
    var onAcceptCompletion: (() -> Bool)?

    override func mouseDown(with event: NSEvent) {
        onFocusIntent?()
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // NSTextView handles command-key input before our panel sees it. Route
        // key equivalents through the app menu so Close/Hide stay menu-driven.
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let activeModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if activeModifiers == .command, event.keyCode == 36 {
            onSubmit?()
            return
        }

        if activeModifiers.isEmpty {
            switch event.keyCode {
            case 126:
                if onMove?(.up, moveContext()) == true {
                    return
                }
            case 125:
                if onMove?(.down, moveContext()) == true {
                    return
                }
            default:
                break
            }
        }

        if activeModifiers.isEmpty, event.keyCode == 36 || event.keyCode == 48 {
            if onAcceptCompletion?() == true {
                return
            }
        }

        super.keyDown(with: event)
    }

    private func moveContext() -> PromptMoveContext {
        PromptMoveContext(isCursorOnLastLine: isCursorOnLastVisualLine)
    }

    private var isCursorOnLastVisualLine: Bool {
        guard selectedRange().length == 0,
              let layoutManager,
              let textContainer
        else {
            return false
        }

        layoutManager.ensureLayout(for: textContainer)

        let textLength = (string as NSString).length
        let cursorLocation = min(selectedRange().location, textLength)
        let cursorGlyphIndex: Int
        if textLength == 0 {
            cursorGlyphIndex = 0
        } else {
            cursorGlyphIndex = layoutManager.glyphIndexForCharacter(at: max(0, min(cursorLocation, textLength - 1)))
        }

        var cursorLineRange = NSRange(location: 0, length: 0)
        _ = layoutManager.lineFragmentRect(forGlyphAt: cursorGlyphIndex, effectiveRange: &cursorLineRange)

        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else {
            return true
        }

        var lastLineRange = NSRange(location: 0, length: 0)
        _ = layoutManager.lineFragmentRect(forGlyphAt: glyphCount - 1, effectiveRange: &lastLineRange)

        return NSIntersectionRange(cursorLineRange, lastLineRange).length > 0
    }
}
