import Foundation
import SwiftUI

struct ActiveMention: Equatable {
    let range: Range<String.Index>
    let location: Int
    let query: String
    let trigger: MentionCompletionKind

    var key: String {
        "\(trigger.rawValue):\(location):\(query)"
    }

    static func detect(in text: String, selection: TextSelection?) -> ActiveMention? {
        guard let selectionRange = selection?.range(in: text),
              selectionRange.isEmpty,
              selectionRange.lowerBound > text.startIndex
        else {
            return nil
        }

        let insertionIndex = selectionRange.lowerBound
        let prefix = text[..<insertionIndex]
        let triggerRanges: [(MentionCompletionKind, Range<String.Index>)] = [
            (.agent, prefix.range(of: MentionCompletionKind.agent.symbol, options: .backwards)),
            (.skill, prefix.range(of: MentionCompletionKind.skill.symbol, options: .backwards))
        ].compactMap { trigger, range in
            range.map { (trigger, $0) }
        }
        guard let (trigger, triggerRange) = triggerRanges.max(by: { $0.1.lowerBound < $1.1.lowerBound }) else {
            return nil
        }

        let queryStart = triggerRange.upperBound
        let query = String(text[queryStart..<insertionIndex])
        guard query.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        return ActiveMention(
            range: triggerRange.lowerBound..<insertionIndex,
            location: text.distance(from: text.startIndex, to: triggerRange.lowerBound),
            query: query,
            trigger: trigger
        )
    }
}

extension TextSelection {
    func range(in text: String) -> Range<String.Index>? {
        switch indices {
        case .selection(let range):
            return range.valid(in: text)
        case .multiSelection(let ranges):
            guard ranges.ranges.count == 1, let range = ranges.ranges.first else {
                return nil
            }
            return range.valid(in: text)
        @unknown default:
            return nil
        }
    }
}

private extension Range where Bound == String.Index {
    func valid(in text: String) -> Range<String.Index>? {
        // SwiftUI can briefly publish a TextSelection from the previous text
        // value while AppKit is still applying an edit. Only use indices that
        // are already valid character boundaries in the current prompt.
        guard text.containsIndexBoundary(lowerBound),
              text.containsIndexBoundary(upperBound),
              lowerBound <= upperBound
        else {
            return nil
        }

        return lowerBound..<upperBound
    }
}

private extension String {
    func containsIndexBoundary(_ index: Index) -> Bool {
        index == endIndex || indices.contains(index)
    }
}
