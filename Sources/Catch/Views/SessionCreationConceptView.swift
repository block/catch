import AppKit
import SwiftUI

/// Session-first creation UI backed by Goose's `goose serve` ACP+ server.
public struct SessionCreationConceptView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var agent: ConceptAgent = .goose
    @State private var model: ConceptModel = ConceptAgent.goose.models[0]
    @State private var project: ConceptProject = .catchProject
    @State private var isDictating = false
    @State private var promptSelection = TextSelectionRange()
    @State private var mentionSelectionIndex = 0
    @State private var suppressedMentionKey: String?
    @State private var fileMentionCompletions: [MentionCompletion] = []
    @State private var modelInventory: [String: [ConceptModel]] = [:]
    @FocusState private var isPromptFocused: Bool

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
            isPromptFocused = true
            loadFileMentions()
            loadModelInventory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPromptField)) { _ in
            isPromptFocused = true
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
                        if displayedMention != nil {
                            moveMentionSelection(direction: direction)
                        } else {
                            store.moveSelection(direction: direction)
                        }
                    },
                    onAccept: {
                        acceptSelectedMention()
                    },
                    onEscape: {
                        if let activeMention {
                            suppressedMentionKey = activeMention.key
                        } else {
                            NSApp.hide(nil)
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
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            PromptTextView(
                text: $store.prompt,
                selection: $promptSelection,
                isFocused: $isPromptFocused,
                onSubmit: submit,
                onMove: moveFromPrompt,
                onAcceptCompletion: acceptSelectedMention
            )
            .frame(height: 150)
        }
    }

    var controlBar: some View {
        HStack(spacing: 8) {
            addMenu
            agentMenu
            modelMenu
            projectMenu

            Spacer(minLength: 8)

            connectionStatus
            dictateButton
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
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Additional inputs are not wired yet")
    }

    var agentMenu: some View {
        Menu {
            ForEach(ConceptAgent.allCases) { option in
                Button {
                    agent = option
                    model = models(for: option)[0]
                    isPromptFocused = true
                } label: {
                    if agent == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            chipLabel {
                Image(systemName: agent.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(agent.tint)
                Text(agent.title)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    var modelMenu: some View {
        Menu {
            ForEach(models(for: agent)) { option in
                Button {
                    model = option
                    isPromptFocused = true
                } label: {
                    if model == option {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            chipLabel {
                Text(model.name)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    var projectMenu: some View {
        Menu {
            ForEach(ConceptProject.allCases) { option in
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
            chipLabel {
                Circle()
                    .fill(project.tint)
                    .frame(width: 8, height: 8)
                Text(project.title)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    func chipLabel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 14, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(Color.primary.opacity(0.1), in: Capsule())
    }

    var connectionStatus: some View {
        Group {
            if store.isConnected {
                Text("⌘↵")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(canSubmit ? 1 : 0)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 24)
                    .help(store.errorMessage ?? "Connecting to Goose")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
    }

    var dictateButton: some View {
        Button {
            isDictating.toggle()
            isPromptFocused = true
        } label: {
            Image(systemName: isDictating ? "waveform" : "mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isDictating ? Color.red : Color.primary)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Dictation is not wired in this branch")
    }

    var sendButton: some View {
        Button {
            submit()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(canSubmit ? Color.white : Color.secondary)
                .frame(width: 38, height: 38)
                .background(canSubmit ? agent.tint : Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .keyboardShortcut(.return, modifiers: [.command])
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
        .help("Start session")
    }

    func submit() {
        let configuration = GooseSessionConfiguration(
            providerID: agent.providerID,
            modelID: model.modelID,
            cwd: project.cwd
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
                        store.selectedSessionID = session.id
                        isPromptFocused = true
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
        let completions = MentionCompletion.agentCompletions(from: ConceptAgent.allCases)
            + MentionCompletion.skillCompletions
            + fileMentionCompletions

        let filtered: [MentionCompletion]
        if normalizedQuery.isEmpty {
            filtered = completions
        } else {
            filtered = completions.filter { completion in
                completion.searchText.lowercased().contains(normalizedQuery)
            }
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

    func moveFromPrompt(direction: SelectionDirection) -> Bool {
        if displayedMention != nil {
            moveMentionSelection(direction: direction)
        } else {
            store.moveSelection(direction: direction)
        }
        return true
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

    func loadModelInventory() {
        Task.detached(priority: .utility) {
            let records = ModelInventoryRecord.loadFromGooseSessionDatabase()
            await MainActor.run {
                var grouped: [String: [ConceptModel]] = [:]
                for record in records {
                    grouped[record.providerID, default: []].append(
                        ConceptModel(record.name, modelID: record.modelID)
                    )
                }

                modelInventory = grouped
                if !models(for: agent).contains(model) {
                    model = models(for: agent)[0]
                }
            }
        }
    }

    func models(for agent: ConceptAgent) -> [ConceptModel] {
        let inventoryModels = agent.modelProviderIDs
            .compactMap { modelInventory[$0] }
            .flatMap { $0 }
            .deduplicatedByID()

        if inventoryModels.isEmpty {
            return agent.models
        }

        return [ConceptModel("Default", modelID: nil)] + inventoryModels
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

    static func < (lhs: MentionCompletion, rhs: MentionCompletion) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    static func agentCompletions(from agents: [ConceptAgent]) -> [MentionCompletion] {
        agents.map { agent in
            MentionCompletion(
                id: "agent:\(agent.title)",
                kind: .agent,
                title: agent.title,
                subtitle: "Agent",
                insertText: "@agent:\(agent.title) ",
                searchText: "\(agent.title) agent \(agent.providerID ?? "goose")"
            )
        }
    }

    static let skillCompletions: [MentionCompletion] = [
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

private struct ModelInventoryRecord: Sendable {
    let providerID: String
    let modelID: String
    let name: String

    static func loadFromGooseSessionDatabase() -> [ModelInventoryRecord] {
        let dbPath = NSHomeDirectory() + "/.local/share/goose/sessions/sessions.db"
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let query = """
        WITH latest AS (
            SELECT provider_id, MAX(COALESCE(last_updated_at, updated_at, created_at)) AS updated_at
            FROM provider_inventory_entries
            GROUP BY provider_id
        )
        SELECT e.provider_id, m.model_id, m.name
        FROM provider_inventory_entries e
        JOIN latest l
            ON l.provider_id = e.provider_id
            AND l.updated_at = COALESCE(e.last_updated_at, e.updated_at, e.created_at)
        JOIN provider_inventory_models m
            ON m.inventory_key = e.inventory_key
        ORDER BY e.provider_id, m.recommended DESC, m.ordinal ASC;
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-tabs", dbPath, query]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let rawOutput = String(data: data, encoding: .utf8) else { return [] }

        return rawOutput
            .split(separator: "\n")
            .compactMap { line in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count >= 3 else { return nil }
                return ModelInventoryRecord(
                    providerID: String(columns[0]),
                    modelID: String(columns[1]),
                    name: String(columns[2])
                )
            }
    }
}

private struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelectionRange
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onMove: (SelectionDirection) -> Bool
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

        let textView = PromptNSTextView()
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 24, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
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

        guard let textView = scrollView.documentView as? PromptNSTextView else { return }
        textView.onSubmit = onSubmit
        textView.onMove = onMove
        textView.onAcceptCompletion = onAcceptCompletion

        if textView.string != text {
            textView.string = text
        }

        let clampedSelection = selection.clamped(to: textView.string)
        if textView.selectedRange() != clampedSelection {
            textView.setSelectedRange(clampedSelection)
        }

        guard isFocused.wrappedValue else { return }

        DispatchQueue.main.async {
            context.coordinator.focusTextView()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextView
        weak var textView: PromptNSTextView?
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
                    self?.parent.isFocused.wrappedValue = true
                    self?.focusTextView()
                }
            }
        }

        func focusTextView() {
            guard let textView, let window = textView.window else { return }

            if window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
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

private final class PromptNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onMove: ((SelectionDirection) -> Bool)?
    var onAcceptCompletion: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        let activeModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if activeModifiers == .command, event.keyCode == 36 {
            onSubmit?()
            return
        }

        if activeModifiers.isEmpty {
            switch event.keyCode {
            case 126:
                if onMove?(.up) == true {
                    return
                }
            case 125:
                if onMove?(.down) == true {
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
}

private struct ConceptRecentRow: View {
    let session: CodexSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.status == .working ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)

            Image(systemName: "bird")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.teal)
                .frame(width: 16)

            Text(session.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(session.lastEvent.isEmpty ? "Goose" : session.lastEvent)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

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
            ["databricks_v2", "databricks"]
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
                ConceptModel("Default", modelID: nil),
                ConceptModel("GPT-5.5", modelID: "compass-openai-gpt-5-5"),
                ConceptModel("Claude Sonnet 4.6", modelID: "goose-claude-4-6-sonnet"),
                ConceptModel("Claude Opus 4.6", modelID: "goose-claude-4-6-opus")
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
                ConceptModel("GPT-5.3 Codex", modelID: "gpt-5.3-codex"),
                ConceptModel("Default", modelID: nil)
            ]
        case .amp:
            [
                ConceptModel("Smart", modelID: "smart"),
                ConceptModel("Default", modelID: nil)
            ]
        case .cursor:
            [
                ConceptModel("Auto", modelID: "auto"),
                ConceptModel("Default", modelID: nil)
            ]
        }
    }
}

private struct ConceptModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let modelID: String?

    init(_ name: String, modelID: String?) {
        id = modelID ?? "default"
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

private enum ConceptProject: CaseIterable, Identifiable {
    case none
    case catchProject
    case nexusCompanion
    case artifacts

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "No project"
        case .catchProject: "catch"
        case .nexusCompanion: "nexus-companion"
        case .artifacts: "goose artifacts"
        }
    }

    var cwd: String {
        switch self {
        case .none: NSHomeDirectory()
        case .catchProject: "/Users/tomb/Development/catch"
        case .nexusCompanion: "/Users/tomb/Development/nexus-companion"
        case .artifacts: "/Users/tomb/goose artifacts"
        }
    }

    var tint: Color {
        switch self {
        case .none: .secondary.opacity(0.4)
        case .catchProject: .blue
        case .nexusCompanion: .green
        case .artifacts: .purple
        }
    }
}
