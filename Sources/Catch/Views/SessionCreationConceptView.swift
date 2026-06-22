import AppKit
import SwiftUI

private let promptFontSize: CGFloat = 19
private let promptInputHorizontalInset: CGFloat = 16
private let promptInputVerticalInset: CGFloat = 12
private let promptInputTopOverflow: CGFloat = 6

/// Session-first creation UI backed by Goose's `goose serve` ACP+ server.
public struct SessionCreationConceptView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var agent: ConceptAgent = .goose
    @State private var model: ConceptModel = ConceptAgent.goose.models[0]
    @State private var reasoningEffort: ReasoningEffort = .off
    @State private var project: GooseProjectOption = .none
    @State private var promptSelection = TextSelectionRange()
    @State private var mentionSelectionIndex = 0
    @State private var suppressedMentionKey: String?
    @State private var gooseAgentCompletions: [MentionCompletion] = GooseBundledAgent.loadMentionCompletions()
    @State private var skillMentionCompletions: [MentionCompletion] = MentionCompletion.defaultSkillCompletions
    @State private var gooseProjects: [GooseProjectOption] = [.none]
    @State private var fileMentionCompletions: [MentionCompletion] = []
    @State private var modelInventory: [String: [ConceptModel]] = [:]
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
            loadFileMentions()
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
        .onChange(of: project.cwd) { _, _ in
            loadFileMentions()
        }
        .background {
            if keyboardMonitorEnabled {
                KeyboardMonitor(
                    onMove: { direction in
                        guard !isPromptFocused else { return false }
                        return moveSessionSelection(direction: direction)
                    },
                    onAccept: {
                        acceptSelectedMention()
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
                Text("Ask \(agent.title) to…")
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
            HStack(spacing: 4) {
                addMenu
                configurationMenu
            }

            Spacer(minLength: 8)

            connectionStatus
            projectMenu
            sendButton
        }
    }
}

// MARK: - Control bar pieces

private extension SessionCreationConceptView {
    var addMenu: some View {
        Menu {
            Button { } label: { Label("Attach File", systemImage: "paperclip") }
            Button { } label: { Label("Add Folder", systemImage: "folder") }
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
        .help("Additional inputs are not wired yet")
    }

    var configurationMenu: some View {
        Menu {
            Section("Agent") {
                ForEach(ConceptAgent.allCases) { option in
                    Button {
                        agent = option
                        model = sortedModels(for: option)[0]
                        isPromptFocused = true
                    } label: {
                        if agent == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }

            Section("Model") {
                ForEach(sortedModels(for: agent)) { option in
                    Button {
                        model = option
                        isPromptFocused = true
                    } label: {
                        if model == option {
                            Label(displayName(for: option), systemImage: "checkmark")
                        } else {
                            Text(displayName(for: option))
                        }
                    }
                }
            }

            Section("Reasoning effort") {
                ForEach(ReasoningEffort.allCases) { option in
                    Button {
                        reasoningEffort = option
                        isPromptFocused = true
                    } label: {
                        if reasoningEffort == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
        } label: {
            CreationMenuLabel(title: modelConfigurationTitle)
        }
        .creationMenuStyle()
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

    var modelConfigurationTitle: String {
        if reasoningEffort == .off {
            displayName(for: model)
        } else {
            "\(displayName(for: model)) \(reasoningEffort.shortTitle)"
        }
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
            providerID: agent.providerID,
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
                        selectSession(session.id)
                    } label: {
                        ConceptRecentRow(
                            session: session,
                            isSelected: store.selectedSessionID == session.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
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
            skillMentionCompletions,
            fileMentionCompletions
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

    func loadFileMentions() {
        let cwd = project.cwd

        Task.detached(priority: .utility) {
            let completions = MentionCompletion.loadFileCompletions(cwd: cwd)
            await MainActor.run {
                guard project.cwd == cwd else { return }
                fileMentionCompletions = completions
            }
        }
    }

    func loadCreationMetadata() {
        Task {
            do {
                let metadata = try await store.loadSessionCreationMetadata()
                apply(metadata)
            } catch {
                if !models(for: agent).contains(model) {
                    model = models(for: agent)[0]
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

        var grouped: [String: [ConceptModel]] = [:]
        for provider in metadata.providers {
            let models = selectedModels(from: provider)
            if !models.isEmpty {
                grouped[provider.providerID] = models
            }
        }
        modelInventory = grouped

        if agent == .goose, let defaults = metadata.defaults, let defaultModel = grouped[defaults.providerID]?.first(where: { $0.modelID == defaults.modelID }) {
            model = defaultModel
        } else if !models(for: agent).contains(model) {
            model = models(for: agent)[0]
        }

        loadFileMentions()
    }

    func selectedModels(from provider: GooseProviderEntry) -> [ConceptModel] {
        let recommended = provider.models.filter(\.recommended)
        let sourceModels = recommended.isEmpty ? provider.models : recommended
        return sourceModels.map { model in
            ConceptModel(model.name, modelID: model.id)
        }.deduplicatedByID()
    }

    func models(for agent: ConceptAgent) -> [ConceptModel] {
        let inventoryModels = agent.modelProviderIDs
            .compactMap { modelInventory[$0] }
            .flatMap { $0 }
            .deduplicatedByID()

        if inventoryModels.isEmpty {
            return agent.models
        }

        if inventoryModels.contains(where: { $0.id == "default" }) {
            return inventoryModels
        }

        guard agent.supportsDefaultModel else {
            return inventoryModels
        }

        return ([ConceptModel("Default", modelID: nil)] + inventoryModels).deduplicatedByID()
    }

    func sortedModels(for agent: ConceptAgent) -> [ConceptModel] {
        models(for: agent).sorted {
            displayName(for: $0, agent: agent).localizedStandardCompare(displayName(for: $1, agent: agent)) == .orderedAscending
        }
    }

    func displayName(for model: ConceptModel, agent: ConceptAgent) -> String {
        guard agent == .claudeCode else {
            return model.name
        }

        return model.name.formattedClaudeCodeModelName
    }

    func displayName(for model: ConceptModel) -> String {
        displayName(for: model, agent: agent)
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
    case file

    static func < (lhs: MentionCompletionKind, rhs: MentionCompletionKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .agent: "Agent"
        case .skill: "Skill"
        case .file: "File"
        }
    }

    var symbolName: String {
        switch self {
        case .agent: "person.crop.circle.badge.plus"
        case .skill: "sparkles"
        case .file: "doc.text"
        }
    }

    var tint: Color {
        switch self {
        case .agent: .teal
        case .skill: .purple
        case .file: .blue
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

    static func loadFileCompletions(cwd: String) -> [MentionCompletion] {
        let rootURL = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let ignoredDirectories: Set<String> = [
            ".build",
            ".git",
            ".swiftpm",
            "DerivedData",
            "dist",
            "node_modules"
        ]
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var completions: [MentionCompletion] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            if values?.isDirectory == true {
                if ignoredDirectories.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }

            let relativePath = fileURL.path
                .replacingOccurrences(of: rootURL.path + "/", with: "")
            guard !relativePath.isEmpty else { continue }

            completions.append(
                MentionCompletion(
                    id: "file:\(relativePath)",
                    kind: .file,
                    title: fileURL.lastPathComponent,
                    subtitle: relativePath,
                    insertText: "@file:\(relativePath) ",
                    searchText: "\(fileURL.lastPathComponent) \(relativePath)"
                )
            )

            if completions.count >= 600 {
                break
            }
        }

        return completions
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
                ProgressView()
                    .controlSize(.mini)
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

// MARK: - UI domain

private enum ConceptAgent: CaseIterable, Identifiable {
    case goose
    case claudeCode
    case codex
    case amp
    case cursor

    var id: Self { self }

    var title: String {
        switch self {
        case .goose: "Goose"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .amp: "Amp"
        case .cursor: "Cursor Agent"
        }
    }

    var providerID: String? {
        switch self {
        case .goose: nil
        case .claudeCode: "claude-acp"
        case .codex: "codex-acp"
        case .amp: "amp-acp"
        case .cursor: "cursor-agent"
        }
    }

    var modelProviderIDs: [String] {
        switch self {
        case .goose:
            ["databricks_v2"]
        case .claudeCode:
            ["claude-acp"]
        case .codex:
            ["codex-acp"]
        case .amp:
            ["amp-acp"]
        case .cursor:
            ["cursor-agent"]
        }
    }

    var symbolName: String {
        switch self {
        case .goose: "bird"
        case .claudeCode: "sparkle"
        case .codex: "terminal"
        case .amp: "bolt"
        case .cursor: "cube"
        }
    }

    var tint: Color {
        switch self {
        case .goose: .teal
        case .claudeCode: .orange
        case .codex: .indigo
        case .amp: .red
        case .cursor: .primary
        }
    }

    var models: [ConceptModel] {
        switch self {
        case .goose:
            [
                ConceptModel("GPT-5.5", modelID: "goose-gpt-5-5"),
                ConceptModel("Claude Sonnet 4.6", modelID: "goose-claude-4-6-sonnet"),
                ConceptModel("Claude Opus 4.8", modelID: "goose-claude-opus-4-8")
            ]
        case .claudeCode:
            [
                ConceptModel("Claude Opus 4.6", modelID: "claude-opus-4-6[1m]"),
                ConceptModel("Sonnet", modelID: "sonnet"),
                ConceptModel("Haiku", modelID: "haiku"),
                ConceptModel("Default", modelID: nil)
            ]
        case .codex:
            [
                ConceptModel("GPT-5.5", modelID: "gpt-5.5"),
                ConceptModel("GPT-5.5 High", modelID: "gpt-5.5-high"),
                ConceptModel("GPT-5.3 Codex", modelID: "gpt-5.3-codex")
            ]
        case .amp:
            [
                ConceptModel("Smart", modelID: "smart")
            ]
        case .cursor:
            [
                ConceptModel("Auto", modelID: "auto")
            ]
        }
    }

    var supportsDefaultModel: Bool {
        self == .claudeCode
    }
}

private struct ConceptModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let modelID: String?

    init(_ name: String, modelID: String?) {
        id = modelID == "default" ? "default" : (modelID ?? "default")
        self.name = name
        self.modelID = modelID
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

private extension String {
    var formattedClaudeCodeModelName: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }

        if trimmed.rangeOfCharacter(from: .uppercaseLetters) != nil {
            return trimmed
        }

        let tokens = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)

        guard tokens.count > 1 else {
            return trimmed.capitalizedModelToken
        }

        var formatted: [String] = []
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            let nextIndex = tokens.index(after: index)

            if token.allSatisfy(\.isNumber),
               nextIndex < tokens.endIndex,
               tokens[nextIndex].first?.isNumber == true
            {
                formatted.append("\(token).\(tokens[nextIndex])")
                index = tokens.index(after: nextIndex)
            } else {
                formatted.append(token.capitalizedModelToken)
                index = nextIndex
            }
        }

        return formatted.joined(separator: " ")
    }

    private var capitalizedModelToken: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
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
                        status: .idle,
                        lastEvent: "Idle"
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
