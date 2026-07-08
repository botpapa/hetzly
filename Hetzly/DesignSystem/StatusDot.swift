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
            .animation(pulseAnimation, value: isPulsing)
            .onAppear { isPulsing = shouldPulse }
            .onChange(of: shouldPulse) { _, newValue in isPulsing = newValue }
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
