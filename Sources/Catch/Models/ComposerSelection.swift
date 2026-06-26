import Foundation

struct ComposerSelectionState: Equatable, Sendable {
    var agent: ComposerSelection?
    var skills: [ComposerSelection]

    init(agent: ComposerSelection? = nil, skills: [ComposerSelection] = []) {
        self.agent = agent
        self.skills = skills
    }

    var selections: [ComposerSelection] {
        [agent].compactMap { $0 } + skills
    }

    mutating func takeConfiguration(
        providerID: String?,
        modelID: String?,
        cwd: String,
        projectID: String?,
        reasoningEffort: String?
    ) -> GooseSessionConfiguration {
        let configuration = GooseSessionConfiguration(
            providerID: providerID,
            modelID: modelID,
            cwd: cwd,
            projectID: projectID,
            reasoningEffort: reasoningEffort,
            invokedAgent: agent?.agentInvocation,
            invokedSkills: skills.compactMap(\.skillInvocation)
        )
        clear()
        return configuration
    }

    mutating func clear() {
        agent = nil
        skills = []
    }
}

struct ComposerSelection: Identifiable, Equatable, Sendable {
    let id: String
    let kind: MentionCompletionKind
    let title: String
    let subtitle: String
    let agentInvocation: GooseInvokedAgent?
    let skillInvocation: GooseInvokedSkill?
}
