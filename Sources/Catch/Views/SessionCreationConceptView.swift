import AppKit
import SwiftUI

/// Session-first creation UI backed by Goose's `goose serve` ACP+ server.
public struct SessionCreationConceptView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var agent: ConceptAgent = .goose
    @State private var model: ConceptModel = ConceptAgent.goose.models[0]
    @State private var project: ConceptProject = .catchProject
    @State private var isDictating = false
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

    public var body: some View {
        VStack(spacing: 0) {
            composer
            Divider().opacity(0.6)
            recentStrip
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .padding(1)
        .onAppear { isPromptFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .focusPromptField)) { _ in
            isPromptFocused = true
        }
        .background {
            if keyboardMonitorEnabled {
                KeyboardMonitor(
                    onMove: { direction in
                        store.moveSelection(direction: direction)
                    },
                    onEscape: {
                        NSApp.hide(nil)
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
                isFocused: $isPromptFocused,
                onSubmit: submit
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
                    model = option.models[0]
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
            ForEach(agent.models) { option in
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
        .frame(height: 132)
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
}

private struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

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
        textView.string = text

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

        if textView.string != text {
            textView.string = text
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
        }
    }
}

private final class PromptNSTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let activeModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if activeModifiers == .command, event.keyCode == 36 {
            onSubmit?()
            return
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
                ConceptModel("Goose GPT-5.5", modelID: "goose-gpt-5-5")
            ]
        case .claudeCode:
            [
                ConceptModel("Claude Opus 4.6", modelID: "claude-opus-4-6[1m]"),
                ConceptModel("Default", modelID: nil)
            ]
        case .codex:
            [
                ConceptModel("GPT-5.5", modelID: "gpt-5.5"),
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

private struct ConceptModel: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let modelID: String?

    init(_ name: String, modelID: String?) {
        self.name = name
        self.modelID = modelID
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
