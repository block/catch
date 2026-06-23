import AppKit
import SwiftUI

private let promptFontSize: CGFloat = 19
private let promptInputHorizontalInset: CGFloat = 16
private let promptInputVerticalInset: CGFloat = 12
private let promptInputTopOverflow: CGFloat = 6
private let sessionActivitySpinnerSize: CGFloat = 11
private let gooseModelProviderID = "databricks_v2"

/// Session-first creation UI backed by Goose's `goose serve` ACP+ server.
public struct SessionCreationConceptView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: SessionStore
    @State private var model: ConceptModel = ConceptModel.fallbackGooseModels[0]
    @State private var reasoningEffort: ReasoningEffort = .off
    @State private var project: GooseProjectOption = .none
    @State private var promptSelection = TextSelectionRange()
    @State private var mentionSelectionIndex = 0
    @State private var suppressedMentionKey: String?
    @State private var gooseAgentCompletions: [MentionCompletion] = GooseBundledAgent.loadMentionCompletions()
    @State private var skillMentionCompletions: [MentionCompletion] = MentionCompletion.defaultSkillCompletions
    @State private var gooseProjects: [GooseProjectOption] = [.none]
    @State private var gooseModels: [ConceptModel] = ConceptModel.fallbackGooseModels
    @State private var isPromptFocused = false

    let keyboardMonitorEnabled: Bool

    public init(keyboardMonitorEnabled: Bool = true) {
        self.keyboardMonitorEnabled = keyboardMonitorEnabled
    }

    private var trimmedPrompt: String {
        store.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedPrompt.isEmpty && store.isConnected
    }

    private var activeMention: ActiveMention? {
        ActiveMention.detect(in: store.prompt, selection: promptSelection)
    }

    private var activeMentionKey: String? {
        activeMention?.key
    }

    private var displayedMention: ActiveMention? {
        guard let activeMention, activeMention.key != suppressedMentionKey else { return nil }
        return activeMention
    }

    private var mentionCompletions: [MentionCompletion] {
        guard let displayedMention else { return [] }
        return completions(matching: displayedMention.query)
    }

    public var body: some View {
        VStack(spacing: 0) {
            composer
            Divider().opacity(0.6)
            completionOrRecentStrip
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .padding(1)
        .onAppear {
            focusPrompt()
            if store.isConnected {
                loadCreationMetadata()
            }
        }
        .onChange(of: isPromptFocused) { _, isFocused in
            if isFocused {
                store.selectedSessionID = nil
            }
        }
        .onChange(of: store.isConnected) { _, isConnected in
            if isConnected {
                loadCreationMetadata()
            }
        }
        .onChange(of: activeMentionKey) { _, _ in
            mentionSelectionIndex = 0
            suppressedMentionKey = nil
        }
        .background {
            if keyboardMonitorEnabled {
                KeyboardMonitor(
                    onMove: { direction in
                        guard !isPromptFocused else { return false }
                        return moveSessionSelection(direction: direction)
                    },
                    onAccept: { key in
                        if acceptSelectedMention() {
                            return true
                        }
                        guard key == .returnKey else { return false }
                        return activateSelectedSession()
                    },
                    onEscape: {
                        if let activeMention {
                            suppressedMentionKey = activeMention.key
                        } else {
                            NotificationCenter.default.post(name: .hideFloatingWindow, object: nil)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Composer

private extension SessionCreationConceptView {
    var composer: some View {
        VStack(alignment: .leading, spacing: 18) {
            promptField
            controlBar
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    var promptField: some View {
        ZStack(alignment: .topLeading) {
            if store.prompt.isEmpty {
                Text("Ask Goose to…")
                    .font(.system(size: promptFontSize, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, promptInputVerticalInset - promptInputTopOverflow)
                    .allowsHitTesting(false)
            }

            PromptTextView(
                text: $store.prompt,
                selection: $promptSelection,
                isFocused: $isPromptFocused,
                onFocus: focusPrompt,
                onSubmit: submit,
                onMove: moveFromPrompt,
                onAcceptCompletion: acceptSelectedMention
            )
            .padding(.horizontal, -promptInputHorizontalInset)
            .padding(.top, -promptInputTopOverflow)
            .frame(height: 150)
        }
    }

    var controlBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: -2) {
                addMenu
                    .padding(.leading, -8)
                configurationMenu
            }

            Spacer(minLength: 8)

            connectionStatus
            projectMenu
            sendButton
                .padding(.trailing, -4)
        }
    }
}

// MARK: - Control bar pieces

private extension SessionCreationConceptView {
    var addMenu: some View {
        Menu {
            Button { } label: { Label("Mention Agent", systemImage: "at") }
            Button { } label: { Label("Add Skill", systemImage: "sparkles") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .regular))
                .frame(width: 30, height: 30)
                .contentShape(Capsule())
        }
        .creationMenuStyle()
        .fixedSize()
        .help("Add agent or skill context")
    }

    var configurationMenu: some View {
        ModelConfigurationMenu(
            model: model,
            reasoningEffort: reasoningEffort,
            recommendedModels: recommendedModels(),
            otherModels: otherModels(),
            onSelectReasoning: { option in
                reasoningEffort = option
                isPromptFocused = true
            },
            onSelectModel: { option in
                model = option
                isPromptFocused = true
            }
        )
        .equatable()
    }

    var projectMenu: some View {
        Menu {
            ForEach(gooseProjects) { option in
                Button {
                    project = option
                    isPromptFocused = true
                } label: {
                    if project == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            CreationMenuLabel(title: project.title)
        }
        .creationMenuStyle()
    }

    var connectionStatus: some View {
        Group {
            if store.isConnected {
                EmptyView()
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 24)
                    .help(store.errorMessage ?? "Connecting to Goose")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
    }

    var sendButton: some View {
        Button {
            submit()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(canSubmit ? Color.white : Color.secondary)
                .frame(width: 30, height: 30)
                .background(canSubmit ? Color.accentColor : Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .keyboardShortcut(.return, modifiers: [.command])
        .help("Start session")
    }

    func submit() {
        let configuration = GooseSessionConfiguration(
            providerID: gooseModelProviderID,
            modelID: model.modelID,
            cwd: project.cwd,
            projectID: project.projectID,
            reasoningEffort: reasoningEffort.acpValue
        )

        Task {
            await store.submitPrompt(configuration: configuration)
            isPromptFocused = true
        }
    }
}

// MARK: - Recent strip

private extension SessionCreationConceptView {
    var completionOrRecentStrip: some View {
        Group {
            if displayedMention != nil {
                mentionStrip
            } else {
                recentStrip
            }
        }
        .frame(height: 132)
    }

    var mentionStrip: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(Array(mentionCompletions.enumerated()), id: \.element.id) { index, completion in
                    Button {
                        accept(completion)
                    } label: {
                        MentionCompletionRow(
                            completion: completion,
                            isSelected: index == mentionSelectionIndex
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
        }
        .overlay {
            if mentionCompletions.isEmpty {
                Text("No @ matches")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    var recentStrip: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(store.sessions) { session in
                    Button {
                        activateSession(session)
                    } label: {
                        ConceptRecentRow(
                            session: session,
                            isSelected: store.selectedSessionID == session.id
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .animation(.snappy(duration: 0.22), value: store.sessions.map(\.id))
        }
        .overlay {
            if store.sessions.isEmpty {
                Text(store.isConnected ? "No sessions yet" : (store.errorMessage ?? "Connecting to Goose…"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
            }
        }
    }

    func completions(matching query: String) -> [MentionCompletion] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let groupedCompletions = [
            gooseAgentCompletions,
            skillMentionCompletions
        ]
        let completions = groupedCompletions.flatMap { $0 }

        if normalizedQuery.isEmpty {
            return groupedCompletions.flatMap { group in
                group.sorted().prefix(8)
            }
        }

        let filtered = completions.filter { completion in
            completion.searchText.lowercased().contains(normalizedQuery)
        }

        return Array(filtered.sorted().prefix(24))
    }

    func moveMentionSelection(direction: SelectionDirection) {
        guard !mentionCompletions.isEmpty else { return }

        switch direction {
        case .up:
            mentionSelectionIndex = max(0, mentionSelectionIndex - 1)
        case .down:
            mentionSelectionIndex = min(mentionCompletions.count - 1, mentionSelectionIndex + 1)
        }
    }

    func moveFromPrompt(direction: SelectionDirection, context: PromptMoveContext) -> Bool {
        if displayedMention != nil {
            moveMentionSelection(direction: direction)
            return true
        }

        guard direction == .down, context.isCursorOnLastLine else {
            return false
        }

        selectFirstSession()
        return store.selectedSessionID != nil
    }

    func moveSessionSelection(direction: SelectionDirection) -> Bool {
        guard !store.sessions.isEmpty else { return false }

        guard let selectedSessionID = store.selectedSessionID,
              let currentIndex = store.sessions.firstIndex(where: { $0.id == selectedSessionID })
        else {
            if direction == .down {
                selectFirstSession()
                return store.selectedSessionID != nil
            }
            return false
        }

        switch direction {
        case .down:
            let nextIndex = min(store.sessions.index(before: store.sessions.endIndex), currentIndex + 1)
            selectSession(store.sessions[nextIndex].id)
        case .up:
            if currentIndex == store.sessions.startIndex {
                focusPromptAtEnd()
            } else {
                let previousIndex = max(store.sessions.startIndex, currentIndex - 1)
                selectSession(store.sessions[previousIndex].id)
            }
        }

        return true
    }

    func selectFirstSession() {
        guard let firstSession = store.sessions.first else { return }
        selectSession(firstSession.id)
    }

    func selectSession(_ id: String) {
        isPromptFocused = false
        store.selectedSessionID = id
    }

    func focusPrompt() {
        store.selectedSessionID = nil
        isPromptFocused = true
    }

    func focusPromptAtEnd() {
        let promptLength = (store.prompt as NSString).length
        promptSelection = TextSelectionRange(location: promptLength, length: 0)
        focusPrompt()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusPromptField, object: nil)
        }
    }

    func acceptSelectedMention() -> Bool {
        guard displayedMention != nil, mentionCompletions.indices.contains(mentionSelectionIndex) else {
            return false
        }

        accept(mentionCompletions[mentionSelectionIndex])
        return true
    }

    func activateSelectedSession() -> Bool {
        guard let session = store.selectedSession else { return false }
        return activateSession(session)
    }

    @discardableResult
    func activateSession(_ session: CodexSession) -> Bool {
        guard let url = session.gooseInternalSessionURL else { return false }
        openURL(url)
        NotificationCenter.default.post(name: .hideFloatingWindow, object: nil)
        return true
    }

    func accept(_ completion: MentionCompletion) {
        guard let displayedMention else { return }

        let text = store.prompt as NSString
        let replacement = completion.insertText
        let updated = text.replacingCharacters(in: displayedMention.range, with: replacement)
        let cursorLocation = displayedMention.range.location + (replacement as NSString).length

        store.prompt = updated
        promptSelection = TextSelectionRange(location: cursorLocation, length: 0)
        mentionSelectionIndex = 0
        suppressedMentionKey = nil
        isPromptFocused = true
    }

    func loadCreationMetadata() {
        Task {
            do {
                let metadata = try await store.loadSessionCreationMetadata()
                apply(metadata)
            } catch {
                if !models().contains(model) {
                    model = models()[0]
                }
            }
        }
    }

    func apply(_ metadata: GooseSessionCreationMetadata) {
        let projects = metadata.sources
            .filter { $0.type == "project" }
            .map(GooseProjectOption.init(source:))
            .sorted()

        gooseProjects = [.none] + projects
        if !gooseProjects.contains(project) {
            project = .none
        }

        let acpAgents = metadata.sources
            .filter { $0.type == "agent" }
            .map(MentionCompletion.init(agentSource:))
            .sorted()
        if acpAgents.isEmpty {
            gooseAgentCompletions = GooseBundledAgent.loadMentionCompletions()
        } else {
            gooseAgentCompletions = acpAgents
        }

        let acpSkills = metadata.sources
            .filter { $0.type == "skill" }
            .map(MentionCompletion.init(skillSource:))
            .sorted()
        if acpSkills.isEmpty {
            skillMentionCompletions = MentionCompletion.defaultSkillCompletions
        } else {
            skillMentionCompletions = acpSkills
        }

        let supportedModels = selectedModels(from: metadata.supportedModels)
        if !supportedModels.isEmpty {
            if gooseModels != supportedModels {
                gooseModels = supportedModels
            }
        } else if let provider = metadata.providers.first(where: { $0.providerID == gooseModelProviderID }) {
            let providerModels = selectedModels(from: provider)
            if !providerModels.isEmpty, gooseModels != providerModels {
                gooseModels = providerModels
            }
        }

        if let defaults = metadata.defaults,
           defaults.providerID == gooseModelProviderID,
           let defaultModel = gooseModels.first(where: { $0.modelID == defaults.modelID })
        {
            if model != defaultModel {
                model = defaultModel
            }
        } else if !models().contains(model) {
            model = models()[0]
        }
    }

    func selectedModels(from provider: GooseProviderEntry) -> [ConceptModel] {
        provider.models.map { model in
            ConceptModel(model.name, modelID: model.id, isRecommended: model.recommended)
        }.deduplicatedByID()
    }

    func selectedModels(from supportedModels: [GooseSupportedModel]) -> [ConceptModel] {
        ConceptModel.gooseModels(from: supportedModels.map(\.id))
    }

    func models() -> [ConceptModel] {
        gooseModels.isEmpty ? ConceptModel.fallbackGooseModels : gooseModels
    }

    func recommendedModels() -> [ConceptModel] {
        let recommended = models().filter(\.isRecommended)
        return recommended.isEmpty ? models() : recommended
    }

    func otherModels() -> [ConceptModel] {
        let recommendedIDs = Set(recommendedModels().map(\.id))
        return models().filter { !recommendedIDs.contains($0.id) }
    }

}

private struct TextSelectionRange: Equatable {
    var location: Int
    var length: Int

    init(location: Int = 0, length: Int = 0) {
        self.location = location
        self.length = length
    }

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    func clamped(to text: String) -> NSRange {
        let textLength = (text as NSString).length
        let clampedLocation = min(max(0, location), textLength)
        let clampedLength = min(max(0, length), textLength - clampedLocation)
        return NSRange(location: clampedLocation, length: clampedLength)
    }
}

private struct ActiveMention: Equatable {
    let range: NSRange
    let query: String

    var key: String {
        "\(range.location):\(range.length):\(query)"
    }

    static func detect(in text: String, selection: TextSelectionRange) -> ActiveMention? {
        let nsText = text as NSString
        guard selection.length == 0, selection.location > 0, selection.location <= nsText.length else {
            return nil
        }

        let prefix = nsText.substring(to: selection.location) as NSString
        let atRange = prefix.range(of: "@", options: .backwards)
        guard atRange.location != NSNotFound else { return nil }

        let queryRange = NSRange(
            location: atRange.location + atRange.length,
            length: selection.location - atRange.location - atRange.length
        )
        let query = nsText.substring(with: queryRange)
        guard query.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        return ActiveMention(
            range: NSRange(location: atRange.location, length: selection.location - atRange.location),
            query: query
        )
    }
}

private enum MentionCompletionKind: Int, Comparable, Sendable {
    case agent
    case skill

    static func < (lhs: MentionCompletionKind, rhs: MentionCompletionKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .agent: "Agent"
        case .skill: "Skill"
        }
    }

    var symbolName: String {
        switch self {
        case .agent: "person.crop.circle.badge.plus"
        case .skill: "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .agent: .teal
        case .skill: .purple
        }
    }
}

private struct MentionCompletion: Identifiable, Comparable, Sendable {
    let id: String
    let kind: MentionCompletionKind
    let title: String
    let subtitle: String
    let insertText: String
    let searchText: String

    init(id: String, kind: MentionCompletionKind, title: String, subtitle: String, insertText: String, searchText: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.insertText = insertText
        self.searchText = searchText
    }

    static func < (lhs: MentionCompletion, rhs: MentionCompletion) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    init(agentSource: GooseSourceEntry) {
        let displayTitle = agentSource.title ?? agentSource.name
        self.init(
            id: "agent:\(agentSource.name)",
            kind: .agent,
            title: displayTitle,
            subtitle: agentSource.description.isEmpty ? "Goose agent" : agentSource.description,
            insertText: "@\(agentSource.name) ",
            searchText: "\(displayTitle) \(agentSource.name) \(agentSource.description)"
        )
    }

    init(skillSource: GooseSourceEntry) {
        let displayTitle = skillSource.title ?? skillSource.name
        self.init(
            id: "skill:\(skillSource.name)",
            kind: .skill,
            title: displayTitle,
            subtitle: skillSource.description.isEmpty ? "Goose skill" : skillSource.description,
            insertText: "@skill:\(skillSource.name) ",
            searchText: "\(displayTitle) \(skillSource.name) \(skillSource.description)"
        )
    }

    static let defaultSkillCompletions: [MentionCompletion] = [
        ("Plan", "Break work into concrete steps", "plan"),
        ("Explore", "Research a codebase or project area", "explore"),
        ("Code Review", "Review changes for bugs and risks", "code-review"),
        ("Debug", "Investigate a failure or runtime issue", "debug"),
        ("Docs", "Use documentation as context", "docs"),
        ("Test", "Run or design verification", "test")
    ].map { name, description, token in
        MentionCompletion(
            id: "skill:\(token)",
            kind: .skill,
            title: name,
            subtitle: description,
            insertText: "@skill:\(token) ",
            searchText: "\(name) \(description) \(token)"
        )
    }
}

private struct MentionCompletionRow: View {
    let completion: MentionCompletion
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: completion.kind.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(completion.kind.tint)
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 1) {
                Text(completion.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !completion.subtitle.isEmpty {
                    Text(completion.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(completion.kind.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelectionRange
    @Binding var isFocused: Bool
    let onFocus: () -> Void
    let onSubmit: () -> Void
    let onMove: (SelectionDirection, PromptMoveContext) -> Bool
    let onAcceptCompletion: () -> Bool

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = PromptNSTextView()
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.systemFont(ofSize: promptFontSize, weight: .regular)
        textView.textColor = .labelColor
        // Inset needed to avoid clipping caret and Voice Control glow.
        textView.textContainerInset = NSSize(width: promptInputHorizontalInset, height: promptInputVerticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onFocusIntent = context.coordinator.focusFromUserInteraction
        textView.onMove = onMove
        textView.onAcceptCompletion = onAcceptCompletion
        textView.string = text
        textView.setSelectedRange(selection.clamped(to: text))

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.startObservingFocusRequests()
        return scrollView
    }

    @MainActor
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.wantsFocus = isFocused

        guard let textView = scrollView.documentView as? PromptNSTextView else { return }
        textView.onSubmit = onSubmit
        textView.onFocusIntent = context.coordinator.focusFromUserInteraction
        textView.onMove = onMove
        textView.onAcceptCompletion = onAcceptCompletion

        if textView.string != text {
            textView.string = text
        }

        let clampedSelection = selection.clamped(to: textView.string)
        if textView.selectedRange() != clampedSelection {
            textView.setSelectedRange(clampedSelection)
        }

        context.coordinator.synchronizeFocusState()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextView
        weak var textView: PromptNSTextView?
        var wantsFocus = false
        nonisolated(unsafe) private var focusObserver: NSObjectProtocol?

        init(parent: PromptTextView) {
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
                Task { @MainActor in
                    self?.parent.isFocused = true
                    self?.wantsFocus = true
                    self?.focusTextView()
                }
            }
        }

        func focusTextView() {
            guard let textView, let window = textView.window else { return }
            guard window.isVisible, window.isKeyWindow else { return }

            if window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        }

        func synchronizeFocusState() {
            if wantsFocus {
                focusTextView()
            } else {
                resignTextViewFocus()
            }
        }

        private func resignTextViewFocus() {
            guard let textView, let window = textView.window else { return }

            if window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
        }

        func focusFromUserInteraction() {
            wantsFocus = true
            parent.onFocus()
        }

        func textDidBeginEditing(_ notification: Notification) {
            focusFromUserInteraction()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            if parent.text != textView.string {
                parent.text = textView.string
            }
            parent.selection = TextSelectionRange(textView.selectedRange())
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selection = TextSelectionRange(textView.selectedRange())
        }
    }
}

private struct PromptMoveContext {
    let isCursorOnLastLine: Bool
}

private final class PromptNSTextView: NSTextView {
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

private struct ConceptRecentRow: View {
    let session: CodexSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(session.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if session.status == .working {
                SessionActivitySpinner()
                    .frame(width: 28, alignment: .trailing)
            } else {
                Text(AppFormatters.compactAge(for: session.updatedAt))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SessionActivitySpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let rotation = reduceMotion
                ? Angle.zero
                : Angle.degrees(
                    (timeline.date.timeIntervalSinceReferenceDate * 360)
                        .truncatingRemainder(dividingBy: 360)
                )

            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.18), lineWidth: 1.4)

                Circle()
                    .trim(from: 0.06, to: 0.34)
                    .stroke(
                        .secondary.opacity(0.82),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
                    )
                    .rotationEffect(rotation)
            }
            .frame(width: sessionActivitySpinnerSize, height: sessionActivitySpinnerSize)
        }
        .accessibilityLabel("Working")
    }
}

// MARK: - UI domain

struct ConceptModel: Identifiable, Equatable, Hashable, Sendable {
    static let fallbackGooseModelIDs = [
        "goose-claude-4-6-sonnet",
        "goose-claude-4-7-opus",
        "goose-claude-fable-5",
        "goose-claude-haiku-4-5",
        "goose-claude-opus-4-8",
        "goose-gpt-5-4-mini",
        "goose-gpt-5-5"
    ]
    static let fallbackGooseModels = gooseModels(from: fallbackGooseModelIDs)

    let id: String
    let name: String
    let modelID: String?
    let isRecommended: Bool

    init(_ name: String, modelID: String?, isRecommended: Bool = false) {
        id = modelID == "default" ? "default" : (modelID ?? "default")
        self.name = name
        self.modelID = modelID
        self.isRecommended = isRecommended
    }

    static func gooseModels(from ids: [String]) -> [ConceptModel] {
        let parsedModels = ids.compactMap(ParsedGooseModel.init(id:))
        let latestModelByFamily = Dictionary(grouping: parsedModels, by: \.familyKey)
            .compactMapValues { models in
                models.max { left, right in
                    left.version.lexicographicallyPrecedes(right.version)
                }?.id
            }

        return parsedModels
            .map { parsed in
                ConceptModel(
                    parsed.displayName,
                    modelID: parsed.id,
                    isRecommended: latestModelByFamily[parsed.familyKey] == parsed.id
                )
            }
            .deduplicatedByID()
            .sorted { left, right in
                let leftRank = ParsedGooseModel(id: left.id)?.sortRank ?? 4
                let rightRank = ParsedGooseModel(id: right.id)?.sortRank ?? 4
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }
}

struct ParsedGooseModel {
    let id: String
    let familyKey: String
    let familyTokens: [String]
    let version: [Int]

    init?(id: String) {
        guard id.hasPrefix("goose-") else { return nil }

        var familyTokens: [String] = []
        var version: [Int] = []
        for token in id.dropFirst("goose-".count).split(separator: "-").map(String.init) {
            if let numericToken = Int(token) {
                version.append(numericToken)
            } else {
                familyTokens.append(token)
            }
        }

        guard !familyTokens.isEmpty, !version.isEmpty else { return nil }

        self.id = id
        self.familyKey = familyTokens.joined(separator: "-")
        self.familyTokens = familyTokens
        self.version = version
    }

    var displayName: String {
        let formattedFamilyTokens = familyTokens.map(Self.formatFamilyToken)
        let versionString = version.map(String.init).joined(separator: ".")

        if formattedFamilyTokens.first == "GPT" {
            let suffix = formattedFamilyTokens.dropFirst().joined(separator: " ")
            return suffix.isEmpty ? "GPT-\(versionString)" : "GPT-\(versionString) \(suffix.lowercased())"
        }

        return (formattedFamilyTokens + [versionString]).joined(separator: " ")
    }

    var sortRank: Int {
        if familyKey == "gpt" { return 0 }
        if familyKey.contains("opus") { return 1 }
        if familyKey.contains("haiku") { return 3 }
        return 2
    }

    private static func formatFamilyToken(_ token: String) -> String {
        switch token.lowercased() {
        case "gpt":
            return "GPT"
        case "chatgpt":
            return "ChatGPT"
        default:
            guard let first = token.first else { return "" }
            return String(first).uppercased() + token.dropFirst().lowercased()
        }
    }
}

private extension Array where Element == ConceptModel {
    func deduplicatedByID() -> [ConceptModel] {
        var seen: Set<String> = []
        var unique: [ConceptModel] = []

        for model in self where seen.insert(model.id).inserted {
            unique.append(model)
        }

        return unique
    }
}

private enum ReasoningEffort: String, CaseIterable, Identifiable {
    case off
    case low
    case medium
    case high
    case max

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Max"
        }
    }

    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Max"
        }
    }

    var acpValue: String? {
        rawValue
    }
}

private struct GooseProjectOption: Identifiable, Equatable, Comparable, Sendable {
    let id: String
    let title: String
    let cwd: String
    let projectID: String?
    let tint: Color

    static let none = GooseProjectOption(
        id: "none",
        title: "No project",
        cwd: NSHomeDirectory(),
        projectID: nil,
        tint: .secondary.opacity(0.4)
    )

    init(id: String, title: String, cwd: String, projectID: String?, tint: Color) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.projectID = projectID
        self.tint = tint
    }

    init(source: GooseSourceEntry) {
        let displayTitle = source.title ?? source.name
        self.init(
            id: source.name,
            title: displayTitle,
            cwd: Self.defaultCWD(for: source),
            projectID: source.name,
            tint: source.color.flatMap(Color.init(hex:)) ?? .purple
        )
    }

    static func < (lhs: GooseProjectOption, rhs: GooseProjectOption) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func defaultCWD(for source: GooseSourceEntry) -> String {
        let artifacts = NSHomeDirectory() + "/goose artifacts"
        if FileManager.default.fileExists(atPath: artifacts) {
            return artifacts
        }

        return NSHomeDirectory()
    }
}

private struct GooseBundledAgent: Sendable {
    let name: String
    let description: String

    static func loadMentionCompletions() -> [MentionCompletion] {
        load().map { agent in
            MentionCompletion(
                id: "agent:\(agent.name)",
                kind: .agent,
                title: agent.name,
                subtitle: agent.description.isEmpty ? "Goose agent" : agent.description,
                insertText: "@\(agent.name) ",
                searchText: "\(agent.name) \(agent.description)"
            )
        }.sorted()
    }

    private static func load() -> [GooseBundledAgent] {
        let agentsDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".agents/agents", isDirectory: true)
        let manifestURL = agentsDirectory.appendingPathComponent(".goose-internal-bundled-agents.json")

        guard let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileNames = object["seededFiles"] as? [String]
        else {
            return fallbackAgents
        }

        let agents = fileNames.compactMap { fileName -> GooseBundledAgent? in
            let url = agentsDirectory.appendingPathComponent(fileName)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return parseAgent(content)
        }

        return agents.isEmpty ? fallbackAgents : agents
    }

    private static func parseAgent(_ content: String) -> GooseBundledAgent? {
        guard content.hasPrefix("---"),
              let endRange = content.range(of: "\n---", range: content.index(content.startIndex, offsetBy: 3)..<content.endIndex)
        else {
            return nil
        }

        let frontmatter = content[content.index(content.startIndex, offsetBy: 3)..<endRange.lowerBound]
        var fields: [String: String] = [:]
        for line in frontmatter.split(separator: "\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            fields[key] = value
        }

        guard let name = fields["name"], !name.isEmpty else { return nil }
        return GooseBundledAgent(name: name, description: fields["description"] ?? "")
    }

    private static let fallbackAgents: [GooseBundledAgent] = [
        GooseBundledAgent(name: "Builderbot", description: "Focused coding partner for thoughtful, efficient implementation."),
        GooseBundledAgent(name: "block.md", description: "Opinionated guide to Block's intelligence operating model.")
    ]
}

private extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private struct ModelConfigurationMenu: View, Equatable {
    let model: ConceptModel
    let reasoningEffort: ReasoningEffort
    let recommendedModels: [ConceptModel]
    let otherModels: [ConceptModel]
    let onSelectReasoning: (ReasoningEffort) -> Void
    let onSelectModel: (ConceptModel) -> Void

    // Native macOS menus are sensitive to identity churn while submenus are
    // presented. Ignore action closure identity so unrelated parent updates
    // such as session refreshes do not rebuild the open menu.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model == rhs.model
            && lhs.reasoningEffort == rhs.reasoningEffort
            && lhs.recommendedModels == rhs.recommendedModels
            && lhs.otherModels == rhs.otherModels
    }

    var body: some View {
        Menu {
            Picker("Reasoning", selection: reasoningSelection) {
                ForEach(ReasoningEffort.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            }
            .pickerStyle(.inline)

            Section("Model") {
                Menu {
                    Picker(selection: modelSelection) {
                        ForEach(recommendedModels) { option in
                            Text(option.name)
                                .tag(option)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if !otherModels.isEmpty {
                        Menu {
                            Picker(selection: modelSelection) {
                                ForEach(otherModels) { option in
                                    Text(option.name)
                                        .tag(option)
                                }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } label: {
                            Text("Other…")
                        }
                    }
                } label: {
                    Text(model.name)
                }
            }
        } label: {
            CreationMenuLabel(title: modelConfigurationTitle)
        }
        .creationMenuStyle()
    }

    private var modelConfigurationTitle: String {
        if reasoningEffort == .off {
            model.name
        } else {
            "\(model.name) \(reasoningEffort.shortTitle)"
        }
    }

    private var reasoningSelection: Binding<ReasoningEffort> {
        Binding(
            get: { reasoningEffort },
            set: { onSelectReasoning($0) }
        )
    }

    private var modelSelection: Binding<ConceptModel> {
        Binding(
            get: { model },
            set: { onSelectModel($0) }
        )
    }
}

private struct CreationMenuLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Capsule())
    }
}

private struct CreationMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CreationMenuButton(configuration: configuration)
    }

    private struct CreationMenuButton: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background {
                    Capsule()
                        .fill(backgroundColor)
                }
                .onHover { isHovered = $0 }
        }

        private var backgroundColor: Color {
            if configuration.isPressed {
                Color.primary.opacity(0.16)
            } else if isHovered {
                Color.primary.opacity(0.08)
            } else {
                Color.clear
            }
        }
    }
}

private extension View {
    func creationMenuStyle() -> some View {
        self
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(CreationMenuButtonStyle())
    }
}

#Preview("Session Creation Concept") {
    SessionCreationConceptPreviewHost()
}

private struct SessionCreationConceptPreviewHost: View {
    @StateObject private var store = SessionStore(appSupportDirectoryName: "CatchPreview")

    var body: some View {
        SessionCreationConceptView(keyboardMonitorEnabled: false)
            .environmentObject(store)
            .frame(width: 560, height: 430)
            .onAppear {
                store.isConnected = true
                store.sessions = [
                    CodexSession(
                        provider: .goose,
                        sessionID: "preview-goose-1",
                        cwd: "~/Development/catch",
                        title: "Square iOS Dependency Graph R...",
                        updatedAt: Date().addingTimeInterval(-240),
                        status: .working,
                        lastEvent: "Working"
                    ),
                    CodexSession(
                        provider: .goose,
                        sessionID: "preview-goose-2",
                        cwd: "~/Development/catch",
                        title: "At symbol",
                        updatedAt: Date().addingTimeInterval(-960),
                        status: .idle,
                        lastEvent: "Idle"
                    ),
                    CodexSession(
                        provider: .claudeCode,
                        sessionID: "preview-claude-1",
                        cwd: "~/Development/catch",
                        title: "Today's date",
                        updatedAt: Date().addingTimeInterval(-3600),
                        status: .idle,
                        lastEvent: "Idle"
                    )
                ]
            }
    }
}
