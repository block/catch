import SwiftUI
import Testing
@testable import CatchKit

@Suite
struct ActiveMentionTests {
    @Test
    func detectsAgentMentionAtInsertionPoint() throws {
        let text = "ask @cod"
        let selection = TextSelection(insertionPoint: text.endIndex)

        let mention = try #require(ActiveMention.detect(in: text, selection: selection))

        #expect(mention.trigger == .agent)
        #expect(mention.query == "cod")
        #expect(text[mention.range] == "@cod")
        #expect(mention.location == 4)
    }

    @Test
    func ignoresMentionWhenSelectionIsRange() {
        let text = "ask @cod"
        let range = text.index(text.endIndex, offsetBy: -3)..<text.endIndex
        let selection = TextSelection(range: range)

        #expect(ActiveMention.detect(in: text, selection: selection) == nil)
    }

    @Test
    func stopsMentionAtWhitespace() {
        let text = "ask @cod now"
        let selection = TextSelection(insertionPoint: text.endIndex)

        #expect(ActiveMention.detect(in: text, selection: selection) == nil)
    }

    @Test
    func exposesInsertionSelectionAsEmptyRange() throws {
        let text = "first\nsecond"
        let insertion = TextSelection(insertionPoint: text.endIndex)

        let range = try #require(insertion.range(in: text))

        #expect(range.isEmpty)
        #expect(range.lowerBound == text.endIndex)
    }

    @Test
    func ignoresSelectionFromDifferentPromptValue() {
        let previousText = "abcdef"
        let currentText = ""
        let staleSelection = TextSelection(insertionPoint: previousText.endIndex)

        #expect(staleSelection.range(in: currentText) == nil)
        #expect(ActiveMention.detect(in: currentText, selection: staleSelection) == nil)
    }

    @Test
    func ignoresMultilineSelectionFromPreviousPromptValue() {
        let previousText = "first line\nsecond line\nthird line"
        let currentText = "first line\nsecond line"
        let staleSelection = TextSelection(insertionPoint: previousText.endIndex)

        #expect(staleSelection.range(in: currentText) == nil)
        #expect(ActiveMention.detect(in: currentText, selection: staleSelection) == nil)
    }

    @Test
    func ignoresSelectionWhoseOffsetFallsInsideDifferentCharacterEncoding() {
        let previousText = "ab"
        let currentText = "é"
        let staleIndex = previousText.index(after: previousText.startIndex)
        let staleSelection = TextSelection(insertionPoint: staleIndex)

        #expect(staleSelection.range(in: currentText) == nil)
        #expect(ActiveMention.detect(in: currentText, selection: staleSelection) == nil)
    }

    @Test
    func ignoresSelectionInsideCurrentPromptCharacterBoundary() {
        let text = "🙂"
        let interiorUTF16Index = String.Index(utf16Offset: 1, in: text)
        let selection = TextSelection(insertionPoint: interiorUTF16Index)

        #expect(selection.range(in: text) == nil)
        #expect(ActiveMention.detect(in: text, selection: selection) == nil)
    }

    @Test
    func ignoresSelectionPastCurrentPromptEnd() {
        let text = "abc"
        let outOfBoundsIndex = String.Index(utf16Offset: 100, in: text)
        let selection = TextSelection(insertionPoint: outOfBoundsIndex)

        #expect(selection.range(in: text) == nil)
        #expect(ActiveMention.detect(in: text, selection: selection) == nil)
    }
}
