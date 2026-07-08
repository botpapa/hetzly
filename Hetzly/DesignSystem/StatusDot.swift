import SwiftUI

/// Coarse-grained lifecycle status for any Hetzner resource shown in the UI.
enum ResourceStatus {
    case running
    case off
    case transitioning
    case error
    case unknown

    var color: Color {
        switch self {
        case .running: HetzlyColors.statusRunning
        case .off: HetzlyColors.statusOff
        case .transitioning: HetzlyColors.statusTransitioning
        case .error: HetzlyColors.statusError
        case .unknown: HetzlyColors.textTertiary
        }
    }

    /// VoiceOver never sees color alone — every dot announces its status name.
    var accessibilityLabel: String {
        switch self {
        case .running: "Running"
        case .off: "Off"
        case .transitioning: "Transitioning"
        case .error: "Error"
        case .unknown: "Unknown status"
        }
    }
}

/// An 8pt status indicator dot. Pulses gently while `.transitioning`, but
/// stays static when Reduce Motion is enabled.
struct StatusDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    let status: ResourceStatus

    init(_ status: ResourceStatus) {
        self.status = status
    }

    private var diameter: CGFloat { 8 }

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: diameter, height: diameter)
            .opacity(pulseOpacity)
            .shadow(color: glowColor, radius: glowRadius)
            .animation(pulseAnimation, value: isPulsing)
            .onAppear { isPulsing = shouldPulse }
            .onChange(of: shouldPulse) { _, newValue in isPulsing = newValue }
            .accessibilityLabel(status.accessibilityLabel)
    }

    private var shouldPulse: Bool {
        status == .transitioning && !reduceMotion
    }

    private var pulseOpacity: Double {
        shouldPulse && isPulsing ? 0.35 : 1
    }

    private var pulseAnimation: Animation? {
        shouldPulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : nil
    }

    /// `.running` gets a subtle, ALWAYS-STATIC ambient glow — a fixed-radius
    /// accent-tinted shadow, no animation attached to it. `.transitioning`
    /// deliberately gets NO glow: it already reads as "in motion" via the
    /// opacity pulse above, and this is the one status this view animates.
    /// Layering a second (glow) effect on `.transitioning` would compete
    /// with that pulse rather than reinforce it, so the two ambient
    /// treatments — pulse for "changing", glow for "healthy" — are
    /// deliberately mutually exclusive per status rather than combined.
    private var glowColor: Color {
        status == .running ? HetzlyColors.statusRunning.opacity(0.5) : .clear
    }

    private var glowRadius: CGFloat {
        status == .running ? 4 : 0
    }
}

extension ResourceStatus: Equatable {}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack { StatusDot(.running); Text("Running").bodySecondary() }
            HStack { StatusDot(.off); Text("Off").bodySecondary() }
            HStack { StatusDot(.transitioning); Text("Transitioning").bodySecondary() }
            HStack { StatusDot(.error); Text("Error").bodySecondary() }
            HStack { StatusDot(.unknown); Text("Unknown").bodySecondary() }
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
