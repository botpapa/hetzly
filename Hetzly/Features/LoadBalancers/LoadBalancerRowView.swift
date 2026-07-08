import HetznerKit
import SwiftUI

/// A load balancer's row in `LoadBalancerListView`: health summary dot,
/// name, type chip, service/target counts.
struct LoadBalancerRowView: View {
    let loadBalancer: LoadBalancer

    private var health: LBHealthSummary { LBHealthSummary(targets: loadBalancer.targets) }

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Circle()
                    .fill(health.color)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(health.label)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(loadBalancer.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip(loadBalancer.loadBalancerType.name)
                        Text(countsLabel)
                            .bodySecondary()
                    }
                }

                Spacer(minLength: Spacing.unit * 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var countsLabel: String {
        let services = loadBalancer.services.count
        let targets = loadBalancer.targets.count
        return "\(services) service\(services == 1 ? "" : "s") · \(targets) target\(targets == 1 ? "" : "s")"
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        LoadBalancerRowView(loadBalancer: LBPreviewFixtures.loadBalancer)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
