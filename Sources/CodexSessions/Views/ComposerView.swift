import SwiftUI

struct ComposerView: View {
    @Binding var prompt: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("New Codex session prompt", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .regular, design: .default))
                .lineLimit(1...3)
                .focused(isFocused)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.45) : Color.accentColor)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}
