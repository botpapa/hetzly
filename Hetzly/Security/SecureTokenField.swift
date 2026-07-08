import SwiftUI

/// A single-line credential entry field: masked by default with an eye
/// button to reveal the plaintext, tuned for pasting API tokens and
/// passwords (no autocapitalization, no autocorrect, monospaced type).
struct SecureTokenField: View {
    let placeholder: String
    @Binding var text: String

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    init(placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .focused($isFocused)
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.password)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide value" : "Reveal value")
        }
    }
}

#Preview {
    @Previewable @State var token = "hcloud_abcdef1234567890"

    return VStack(spacing: 20) {
        SecureTokenField(placeholder: "API Token", text: $token)
        SecureTokenField(placeholder: "API Token", text: .constant(""))
    }
    .padding()
    .preferredColorScheme(.dark)
}
