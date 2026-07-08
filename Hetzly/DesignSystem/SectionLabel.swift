import SwiftUI

/// Uppercase section header: 13pt, 1.5pt tracking, tertiary text color.
struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(HetzlyColors.textTertiary)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        SectionLabel("Servers")
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
