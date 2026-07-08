import SwiftUI

/// Wizard chrome shown above the step content: a leading control (Cancel on
/// step 1, a back chevron afterward) and four progress dots — filled for the
/// current step and everything already completed.
struct CreateServerStepHeader: View {
    let step: CreateServerStep
    var onBack: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack {
            leadingControl
            Spacer()
            dots
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if step == .location {
            Button("Cancel", action: onCancel)
                .secondaryCTAStyle()
        } else {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Back")
        }
    }

    private var dots: some View {
        HStack(spacing: Spacing.unit * 2) {
            ForEach(CreateServerStep.allCases) { candidate in
                Circle()
                    .fill(candidate.rawValue <= step.rawValue ? HetzlyColors.accent : HetzlyColors.textTertiary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 6) {
            CreateServerStepHeader(step: .location, onBack: {}, onCancel: {})
            CreateServerStepHeader(step: .type, onBack: {}, onCancel: {})
            CreateServerStepHeader(step: .config, onBack: {}, onCancel: {})
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
