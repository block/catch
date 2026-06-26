import Foundation

struct MentionCompletion: Identifiable, Comparable, Sendable {
    let id: String
    let kind: MentionCompletionKind
    let title: String
    let subtitle: String
    let searchText: String
    let selection: ComposerSelection

    init(
        id: String,
        kind: MentionCompletionKind,
        title: String,
        subtitle: String,
        searchText: String,
        selection: ComposerSelection
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.searchText = searchText
        self.selection = selection
    }

    static func < (lhs: MentionCompletion, rhs: MentionCompletion) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    init(agentSource: GooseSourceEntry) {
        let displayTitle = agentSource.title ?? agentSource.name
        let sourceID = agentSource.path ?? "agent:\(agentSource.name)"
        let agentInvocation = agentSource.path.map { personaID in
            GooseInvokedAgent(
                personaID: personaID,
                displayName: displayTitle,
                systemPrompt: agentSource.content
            )
        }
        let selection = ComposerSelection(
            id: "agent:\(sourceID)",
            kind: .agent,
            title: displayTitle,
            subtitle: agentSource.description,
            agentInvocation: agentInvocation,
            skillInvocation: nil
        )
        self.init(
            id: selection.id,
            kind: .agent,
            title: displayTitle,
            subtitle: agentSource.description.isEmpty ? "Goose agent" : agentSource.description,
            searchText: "\(displayTitle) \(agentSource.name) \(agentSource.description)",
            selection: selection
        )
    }

    init(skillSource: GooseSourceEntry) {
        let displayTitle = skillSource.title ?? skillSource.name
        let sourceID = skillSource.path ?? "\(skillSource.type):\(skillSource.name)"
        let skillInvocation = GooseInvokedSkill(
            id: sourceID,
            displayName: skillSource.name
        )
        let selection = ComposerSelection(
            id: "skill:\(sourceID)",
            kind: .skill,
            title: displayTitle,
            subtitle: skillSource.description,
            agentInvocation: nil,
            skillInvocation: skillInvocation
        )
        self.init(
            id: selection.id,
            kind: .skill,
            title: displayTitle,
            subtitle: skillSource.description.isEmpty ? "Goose skill" : skillSource.description,
            searchText: "\(displayTitle) \(skillSource.name) \(skillSource.description)"
                + " \(skillSource.type)",
            selection: selection
        )
    }
}
