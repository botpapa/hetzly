import SwiftUI

/// Shown by any Hetzly widget when there's no snapshot yet in the App Group
/// container — i.e. the app has never run since the widget was added, or
/// the container is unreachable for some other reason. `compact` trims the
/// copy down to fit `accessoryCircular`'s tiny canvas.
struct EmptyStateView: View {
    var compact = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(WidgetColors.textTertiary)
            if !compact {
                Text("Open Hetzly to sync")
                    .font(.caption2)
                    .foregroundStyle(WidgetColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(8)
    }
}

#Preview {
    EmptyStateView()
        .background(WidgetColors.canvas)
        .preferredColorScheme(.dark)
}
