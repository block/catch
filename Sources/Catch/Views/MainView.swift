import AppKit
import SwiftUI

private let promptFontSize: CGFloat = 17
private let sessionActivitySpinnerSize: CGFloat = 11
let mainViewWidth: CGFloat = 480
let mainViewHeight: CGFloat = 385
private let promptFieldHeight: CGFloat = 105
private let gooseModelProviderID = "databricks_v2"

/// Session-first creation UI backed by Goose's `goose serve` ACP+ server.
public struct MainView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: SessionStore
    @State private var model: MainViewModel = MainViewModel.fallbackGooseModels[0]
    @State private var reasoningEffort: ReasoningEffort = .off
    @State private var project: GooseProjectOption = .none
    @State private var promptSelection: TextSelection?
    @State private var mentionSelectionIndex = 0
    @State private var suppressedMentionKey: String?
    @State private var gooseAgentCompletions: [MentionCompletion] = []
    @State private var skillMentionCompletions: [MentionCompletion] = []
    @State private var composerSelections = ComposerSelectionState()
    @State private var gooseProjects: [GooseProjectOption] = [.none]
    @State private var gooseModels: [MainViewModel] = MainViewModel.fallbackGooseModels
    @State private var promptDownMoveGeneration = 0
    @FocusState private var isPromptFocused: Bool

    let keyboardMonitorEnabled: Bool

    public init(keyboardMonitorEnabled: Bool = true) {
        self.keyboardMonitorEnabled = keyboardMonitorEnabled
    }

    private var canSubmit: Bool {
        store.isConnected
            && (!store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !composerSelections.skills.isEmpty)
    }

    private var selectedComposables: [ComposerSelection] {
        composerSelections.selections
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

private extension MainView {
    var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !selectedComposables.isEmpty {
                selectionChips
            }
            promptField
            controlBar
        }
        .padding(.horizontal, 22)
        .padding(.top, selectedComposables.isEmpty ? 24 : 16)
        .padding(.bottom, 18)
    }

    var selectionChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(selectedComposables) { selection in
                ComposerSelectionChip(selection: selection) {
                    remove(selection)
                }
            }
        }
        .padding(.bottom, 2)
    }

    var promptField: some View {
        TextField(
            text: $store.prompt,
            selection: $promptSelection,
            prompt: Text("Chat with Goose, @ for agents, or / for skills"),
            axis: .vertical
        ) {
            Text("Prompt")
        }
        .font(.system(size: promptFontSize, weight: .regular))
        .foregroundStyle(.primary)
        .textFieldStyle(.plain)
        .lineLimit(...4)
        .focused($isPromptFocused)
        .onTapGesture {
            focusPrompt()
        }
        .onKeyPress(.return, phases: [.down, .repeat]) { keyPress in
            if keyPress.modifiers == .command {
                submit()
                return .handled
            }

            if acceptSelectedMention() {
                return .handled
            }

            insertPromptText("\n")
            return .handled
        }
        .onKeyPress(.tab) {
            acceptSelectedMention() ? .handled : .ignored
        }
        .onKeyPress(.upArrow) {
            guard displayedMention != nil else { return .ignored }
            moveMentionSelection(direction: .up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            if displayedMention != nil {
                moveMentionSelection(direction: .down)
                return .handled
            }

            handOffPromptDownIfNativeMoveStaysPut()
            return .ignored
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: promptFieldHeight)
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

private extension MainView {
    var addMenu: some View {
        Menu {
            Button {
                showCompletions(for: .agent)
            } label: {
                Label {
                    Text("Agent")
                } icon: {
                    Image(nsImage: AddMenuIcon.agent)
                }
            }

            Button {
                showCompletions(for: .skill)
            } label: {
                Label {
                    Text("Skill")
                } icon: {
                    Image(nsImage: AddMenuIcon.skill)
                }
            }
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
                focusPrompt()
            },
            onSelectModel: { option in
                model = option
                focusPrompt()
            }
        )
        .equatable()
    }

    var projectMenu: some View {
        Menu {
            ForEach(gooseProjects) { option in
                Button {
                    project = option
                    focusPrompt()
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
        let configuration = composerSelections.takeConfiguration(
            providerID: gooseModelProviderID,
            modelID: model.modelID,
            cwd: project.cwd,
            projectID: project.projectID,
            reasoningEffort: reasoningEffort.acpValue
        )

        Task {
            await store.submitPrompt(configuration: configuration)
            focusPrompt()
        }
    }
}

// MARK: - Recent strip

private extension MainView {
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
                Text("No \(displayedMention?.trigger.symbol ?? "") matches")
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
                        SessionRow(
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
        guard let displayedMention else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let completions: [MentionCompletion] = switch displayedMention.trigger {
        case .agent:
            gooseAgentCompletions
        case .skill:
            skillMentionCompletions
        }

        if normalizedQuery.isEmpty {
            return Array(completions.sorted().prefix(16))
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

    func handOffPromptDownIfNativeMoveStaysPut() {
        guard let originalSelection = promptSelection?.range(in: store.prompt),
              originalSelection.isEmpty
        else { return }

        let originalPrompt = store.prompt
        let originalCursor = PromptCursorSnapshot(index: originalSelection.lowerBound, in: originalPrompt)
        promptDownMoveGeneration &+= 1
        let generation = promptDownMoveGeneration

        DispatchQueue.main.async {
            guard promptDownMoveGeneration == generation,
                  isPromptFocused,
                  store.selectedSessionID == nil,
                  store.prompt == originalPrompt,
                  let currentSelection = promptSelection?.range(in: store.prompt),
                  currentSelection.isEmpty
            else { return }

            let currentCursor = PromptCursorSnapshot(index: currentSelection.lowerBound, in: store.prompt)
            if currentCursor == originalCursor {
                selectFirstSession()
            }
        }
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
        requestPromptFocus()
    }

    func requestPromptFocus() {
        isPromptFocused = true
    }

    func focusPromptAtEnd() {
        promptSelection = TextSelection(insertionPoint: store.prompt.endIndex)
        focusPrompt()
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
    func activateSession(_ session: Session) -> Bool {
        guard let url = session.berdSessionURL else { return false }
        openURL(url)
        NotificationCenter.default.post(name: .hideFloatingWindow, object: nil)
        return true
    }

    func accept(_ completion: MentionCompletion) {
        guard let displayedMention else { return }

        let cursor = PromptCursorSnapshot(index: displayedMention.range.lowerBound, in: store.prompt)
        var updated = store.prompt
        updated.replaceSubrange(displayedMention.range, with: "")
        updated = updated
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)

        store.prompt = updated
        promptSelection = TextSelection(insertionPoint: cursor.index(in: updated))
        select(completion)
        mentionSelectionIndex = 0
        suppressedMentionKey = nil
        focusPrompt()
    }

    func select(_ completion: MentionCompletion) {
        switch completion.selection.kind {
        case .agent:
            composerSelections.agent = completion.selection
        case .skill:
            if !composerSelections.skills.contains(where: { $0.id == completion.selection.id }) {
                composerSelections.skills.append(completion.selection)
            }
        }
        focusPrompt()
    }

    func remove(_ selection: ComposerSelection) {
        switch selection.kind {
        case .agent:
            if composerSelections.agent?.id == selection.id {
                composerSelections.agent = nil
            }
        case .skill:
            composerSelections.skills.removeAll { $0.id == selection.id }
        }
        focusPrompt()
    }

    func insertPromptText(_ replacement: String) {
        let replacementRange = promptSelection?.range(in: store.prompt) ?? store.prompt.endIndex..<store.prompt.endIndex
        let cursor = PromptCursorSnapshot(index: replacementRange.lowerBound, in: store.prompt)
            .advanced(by: replacement.count)
        var updated = store.prompt
        updated.replaceSubrange(replacementRange, with: replacement)
        store.prompt = updated
        promptSelection = TextSelection(insertionPoint: cursor.index(in: updated))
    }

    func showCompletions(for trigger: MentionCompletionKind) {
        if displayedMention?.trigger == trigger {
            focusPrompt()
            return
        }

        let replacementRange = activeMention?.range ?? promptSelection?.range(in: store.prompt) ?? store.prompt.endIndex..<store.prompt.endIndex
        let replacement = trigger.symbol
        let cursor = PromptCursorSnapshot(index: replacementRange.lowerBound, in: store.prompt)
            .advanced(by: replacement.count)
        var updated = store.prompt
        updated.replaceSubrange(replacementRange, with: replacement)
        store.prompt = updated
        promptSelection = TextSelection(insertionPoint: cursor.index(in: updated))
        mentionSelectionIndex = 0
        suppressedMentionKey = nil
        focusPrompt()
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
        let projects = metadata.projectSources
            .map(GooseProjectOption.init(source:))
            .sorted()

        gooseProjects = [.none] + projects
        if !gooseProjects.contains(project) {
            project = .none
        }

        let acpAgents = metadata.agentSources
            .map(MentionCompletion.init(agentSource:))
            .sorted()
        gooseAgentCompletions = acpAgents
        if let selectedAgent = composerSelections.agent,
           !acpAgents.contains(where: { $0.selection.id == selectedAgent.id })
        {
            composerSelections.agent = nil
        }

        let acpSkills = metadata.skillSources
            .map(MentionCompletion.init(skillSource:))
            .sorted()
        skillMentionCompletions = acpSkills
        let availableSkillIDs = Set(acpSkills.map(\.selection.id))
        composerSelections.skills.removeAll { !availableSkillIDs.contains($0.id) }

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

    func selectedModels(from provider: GooseProviderEntry) -> [MainViewModel] {
        provider.models.map { model in
            MainViewModel(model.name, modelID: model.id, isRecommended: model.recommended)
        }.deduplicatedByID()
    }

    func selectedModels(from supportedModels: [GooseSupportedModel]) -> [MainViewModel] {
        MainViewModel.gooseModels(from: supportedModels.map(\.id))
    }

    func models() -> [MainViewModel] {
        gooseModels.isEmpty ? MainViewModel.fallbackGooseModels : gooseModels
    }

    func recommendedModels() -> [MainViewModel] {
        let recommended = models().filter(\.isRecommended)
        return recommended.isEmpty ? models() : recommended
    }

    func otherModels() -> [MainViewModel] {
        let recommendedIDs = Set(recommendedModels().map(\.id))
        return models().filter { !recommendedIDs.contains($0.id) }
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

private struct ComposerSelectionChip: View {
    let selection: ComposerSelection
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onRemove) {
                ZStack {
                    Image(systemName: selection.kind.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(isHovered ? 0 : 1)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(isHovered ? 0.72 : 0)
                }
                .frame(width: 15, height: 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(chipForeground)
            .help("Remove \(selection.title)")

            Text(selection.title)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(chipForeground)
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .frame(height: 28)
        .background(chipBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(selection.title)
    }

    private var chipBackground: Color {
        switch selection.kind {
        case .agent:
            Color(red: 0.88, green: 0.92, blue: 1.00)
        case .skill:
            Color(red: 1.00, green: 0.94, blue: 0.78)
        }
    }

    private var chipForeground: Color {
        switch selection.kind {
        case .agent:
            Color(red: 0.16, green: 0.36, blue: 0.85)
        case .skill:
            Color(red: 0.48, green: 0.28, blue: 0.02)
        }
    }
}

private struct PromptCursorSnapshot: Equatable {
    private let offset: Int

    init(index: String.Index, in text: String) {
        offset = text.distance(from: text.startIndex, to: index)
    }

    private init(offset: Int) {
        self.offset = offset
    }

    func advanced(by distance: Int) -> PromptCursorSnapshot {
        PromptCursorSnapshot(offset: offset + distance)
    }

    func index(in text: String) -> String.Index {
        text.index(text.startIndex, offsetBy: min(max(0, offset), text.count))
    }
}

private struct SessionRow: View {
    let session: Session
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
                Text(AppFormatters.compactAge(for: session.activityAt))
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
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                    SelectedRowScrollAnchor()
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SelectedRowScrollAnchor: NSViewRepresentable {
    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleScroll(for: view, coordinator: context.coordinator)
        return view
    }

    @MainActor
    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleScroll(for: nsView, coordinator: context.coordinator)
    }

    @MainActor
    private func scheduleScroll(for view: NSView, coordinator: Coordinator, attempt: Int = 0) {
        guard !coordinator.didRequestScroll else { return }

        Task { @MainActor [weak view, weak coordinator] in
            guard let view, let coordinator, !coordinator.didRequestScroll else { return }

            guard view.window != nil, view.enclosingScrollView != nil else {
                if attempt < 5 {
                    scheduleScroll(for: view, coordinator: coordinator, attempt: attempt + 1)
                }
                return
            }

            coordinator.didRequestScroll = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                // `scrollToVisible` performs the minimum scroll needed and is a
                // no-op when the selected row is already fully visible.
                view.scrollToVisible(view.bounds)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var didRequestScroll = false
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

private struct ModelConfigurationMenu: View, Equatable {
    let model: MainViewModel
    let reasoningEffort: ReasoningEffort
    let recommendedModels: [MainViewModel]
    let otherModels: [MainViewModel]
    let onSelectReasoning: (ReasoningEffort) -> Void
    let onSelectModel: (MainViewModel) -> Void

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

    private var modelSelection: Binding<MainViewModel> {
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

#Preview("Main View") {
    MainViewPreviewHost()
}

private struct MainViewPreviewHost: View {
    @StateObject private var store = SessionStore(appSupportDirectoryName: "CatchPreview")

    var body: some View {
        MainView(keyboardMonitorEnabled: false)
            .environmentObject(store)
            .frame(width: mainViewWidth, height: mainViewHeight)
            .onAppear {
                store.isConnected = true
                store.sessions = Session.previewSessions
            }
    }
}
