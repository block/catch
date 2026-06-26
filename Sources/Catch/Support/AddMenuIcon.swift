import AppKit

@MainActor
enum AddMenuIcon {
    static let agent = glyph("@")
    static let skill = glyph("/")

    private static func glyph(_ value: String) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: true) { rect in
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            let attributedGlyph = NSAttributedString(string: value, attributes: attributes)
            let glyphSize = attributedGlyph.size()
            let drawingRect = NSRect(
                x: 0,
                y: max(0, rect.midY - glyphSize.height / 2),
                width: rect.width,
                height: glyphSize.height
            )
            attributedGlyph.draw(in: drawingRect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
