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
        guard let lowerUTF16 = lowerBound.samePosition(in: text.utf16),
              let upperUTF16 = upperBound.samePosition(in: text.utf16),
              let lower = String.Index(lowerUTF16, within: text),
              let upper = String.Index(upperUTF16, within: text),
              lower <= upper
        else {
            return nil
        }

        return lower..<upper
    }
}
