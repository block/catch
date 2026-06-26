import Foundation

struct ActiveMention: Equatable {
    let range: NSRange
    let query: String
    let trigger: MentionCompletionKind

    var key: String {
        "\(trigger.rawValue):\(range.location):\(range.length):\(query)"
    }

    static func detect(in text: String, selection: TextSelectionRange) -> ActiveMention? {
        let nsText = text as NSString
        guard selection.length == 0, selection.location > 0, selection.location <= nsText.length else {
            return nil
        }

        let prefix = nsText.substring(to: selection.location) as NSString
        let triggerRanges: [(MentionCompletionKind, NSRange)] = [
            (.agent, prefix.range(of: MentionCompletionKind.agent.symbol, options: .backwards)),
            (.skill, prefix.range(of: MentionCompletionKind.skill.symbol, options: .backwards))
        ].filter { $0.1.location != NSNotFound }
        guard let (trigger, triggerRange) = triggerRanges.max(by: { $0.1.location < $1.1.location }) else {
            return nil
        }

        let queryRange = NSRange(
            location: triggerRange.location + triggerRange.length,
            length: selection.location - triggerRange.location - triggerRange.length
        )
        let query = nsText.substring(with: queryRange)
        guard query.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        return ActiveMention(
            range: NSRange(location: triggerRange.location, length: selection.location - triggerRange.location),
            query: query,
            trigger: trigger
        )
    }
}
