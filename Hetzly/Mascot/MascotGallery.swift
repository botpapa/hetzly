import SwiftUI

/// A design-review grid showing every `MascotState` animating side by side.
///
/// This is how Hetzi's art gets judged: all eight states, same scale, same
/// dark glass background the mascot will actually appear on. Not used by any
/// production flow — it exists purely so the sprite work is easy to eyeball.
struct MascotGallery: View {
    private let scale: CGFloat = 3
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 24)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(MascotState.allCases, id: \.self) { state in
                    VStack(spacing: 12) {
                        MascotView(state: state, scale: scale)
                        Text(state.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0xA2 / 255))
                            .textCase(.uppercase)
                            .tracking(1.5)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
                }
            }
            .padding(24)
        }
        .background(Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0C / 255))
    }
}

#Preview {
    MascotGallery()
        .preferredColorScheme(.dark)
}
