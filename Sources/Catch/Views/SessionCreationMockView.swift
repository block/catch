import SwiftUI

public struct SessionCreationMockView: View {
    @State private var prompt = ""
    @State private var selectedAgent: MockAgent = .claudeCode
    @State private var selectedModel = MockAgent.claudeCode.models[0]
    @State private var selectedProject = MockProject.none
    @State private var selectedSessionID = MockRecentSession.samples[0].id
    @State private var isAgentPickerPresented = false
    @State private var isProjectPickerPresented = false
    @State private var isRecording = false
    @FocusState private var isPromptFocused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            creationSurface

            Divider()

            recentSessions
        }
        .frame(width: 560, height: 430)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .padding(1)
        .onAppear {
            isPromptFocused = true
        }
    }

    private var creationSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            promptEditor

            HStack(spacing: 8) {
                IconButton(systemName: "plus") {
                    isPromptFocused = true
                }

                agentChip
                projectChip

                Spacer(minLength: 8)

                IconButton(systemName: isRecording ? "mic.fill" : "mic") {
                    isRecording.toggle()
                }
                .foregroundStyle(isRecording ? .red : .primary)

                Button {
                    prompt = ""
                    isPromptFocused = true
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.primary.opacity(0.08) : Color.accentColor)
                        .foregroundStyle(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.primary : Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $prompt)
                .font(.system(size: 22, weight: .regular))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isPromptFocused)
                .frame(minHeight: 132, maxHeight: .infinity)

            if prompt.isEmpty {
                Text("Ask an agent to start a session")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 170)
    }

    private var agentChip: some View {
        Button {
            isAgentPickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedAgent.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selectedAgent.tint)

                Text(selectedModel.name)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isAgentPickerPresented, arrowEdge: .bottom) {
            AgentModelPicker(
                selectedAgent: $selectedAgent,
                selectedModel: $selectedModel
            )
            .frame(width: 470, height: 330)
        }
    }

    private var projectChip: some View {
        Button {
            isProjectPickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(selectedProject.tint)
                    .frame(width: 10, height: 10)

                Text(selectedProject.title)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isProjectPickerPresented, arrowEdge: .bottom) {
            ProjectPicker(selectedProject: $selectedProject)
                .frame(width: 260)
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 2) {
                ForEach(MockRecentSession.samples) { session in
                    Button {
                        selectedSessionID = session.id
                        isPromptFocused = true
                    } label: {
                        RecentSessionMockRow(
                            session: session,
                            isSelected: selectedSessionID == session.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(height: 142)
    }
}

private struct AgentModelPicker: View {
    @Binding var selectedAgent: MockAgent
    @Binding var selectedModel: MockModel

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Agent")
                    .font(.system(size: 14, weight: .semibold))

                ForEach(MockAgent.allCases) { agent in
                    Button {
                        guard agent.isAvailable else { return }

                        selectedAgent = agent
                        selectedModel = agent.models[0]
                    } label: {
                        PickerRow(
                            title: agent.title,
                            systemName: agent.symbolName,
                            tint: agent.tint,
                            isSelected: selectedAgent == agent,
                            isEnabled: agent.isAvailable
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!agent.isAvailable)
                }
            }
            .frame(width: 210, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text("Model")
                    .font(.system(size: 14, weight: .semibold))

                ForEach(selectedAgent.models) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        HStack {
                            Text(model.name)
                                .lineLimit(1)

                            Spacer()

                            if selectedModel == model {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background {
                            if selectedModel == model {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 190, alignment: .leading)
        }
        .padding(22)
        .background(.regularMaterial)
    }
}

private struct ProjectPicker: View {
    @Binding var selectedProject: MockProject

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MockProject.allCases) { project in
                Button {
                    selectedProject = project
                } label: {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(project.tint)
                            .frame(width: 10, height: 10)

                        Text(project.title)
                            .lineLimit(1)

                        Spacer()

                        if selectedProject == project {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background {
                        if selectedProject == project {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.regularMaterial)
    }
}

private struct PickerRow: View {
    let title: String
    let systemName: String
    let tint: Color
    let isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? tint : Color.secondary.opacity(0.45))
                .frame(width: 20)

            Text(title)
                .lineLimit(1)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
    }
}

private struct RecentSessionMockRow: View {
    let session: MockRecentSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: session.agent.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(session.agent.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(session.agent.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(session.age)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            }
        }
    }
}

private struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color.primary.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private enum MockAgent: CaseIterable, Identifiable {
    case goose
    case claudeCode
    case codex
    case copilot
    case amp
    case cursor

    var id: Self { self }

    var title: String {
        switch self {
        case .goose: "Goose"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .copilot: "Copilot"
        case .amp: "Amp"
        case .cursor: "Cursor Agent"
        }
    }

    var symbolName: String {
        switch self {
        case .goose: "bird"
        case .claudeCode: "spark"
        case .codex: "terminal"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .amp: "arrow.up.forward"
        case .cursor: "cube.fill"
        }
    }

    var tint: Color {
        switch self {
        case .goose: .primary
        case .claudeCode: .orange
        case .codex: .indigo
        case .copilot: .gray
        case .amp: .red
        case .cursor: .primary
        }
    }

    var isAvailable: Bool {
        switch self {
        case .codex, .copilot:
            false
        default:
            true
        }
    }

    var models: [MockModel] {
        switch self {
        case .goose:
            [
                MockModel(name: "Claude Opus 4.1"),
                MockModel(name: "Claude Sonnet 4"),
                MockModel(name: "Default")
            ]
        case .claudeCode:
            [
                MockModel(name: "Claude Opus 4.1"),
                MockModel(name: "Default"),
                MockModel(name: "Haiku"),
                MockModel(name: "Sonnet")
            ]
        case .codex:
            [
                MockModel(name: "GPT-5"),
                MockModel(name: "GPT-5 Thinking")
            ]
        case .copilot:
            [MockModel(name: "Default")]
        case .amp:
            [
                MockModel(name: "Default"),
                MockModel(name: "Fast")
            ]
        case .cursor:
            [
                MockModel(name: "Default"),
                MockModel(name: "Max")
            ]
        }
    }
}

private struct MockModel: Identifiable, Equatable {
    let id = UUID()
    let name: String
}

private enum MockProject: CaseIterable, Identifiable {
    case none
    case catchProject
    case nexusCompanion
    case scratch

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "No project"
        case .catchProject: "catch"
        case .nexusCompanion: "nexus-companion"
        case .scratch: "Scratch"
        }
    }

    var tint: Color {
        switch self {
        case .none: .secondary.opacity(0.45)
        case .catchProject: .blue
        case .nexusCompanion: .green
        case .scratch: .purple
        }
    }
}

private struct MockRecentSession: Identifiable {
    let id: String
    let title: String
    let agent: MockAgent
    let age: String

    static let samples = [
        MockRecentSession(id: "1", title: "Fix SwiftUI preview scheme", agent: .codex, age: "3m"),
        MockRecentSession(id: "2", title: "Banana test session", agent: .claudeCode, age: "11m"),
        MockRecentSession(id: "3", title: "Release workflow cleanup", agent: .goose, age: "42m")
    ]
}
