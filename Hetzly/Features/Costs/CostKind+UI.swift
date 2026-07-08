import HetznerKit
import SwiftUI

/// Icon, display name, and categorical tint for each `CostKind`, so the
/// Costs feature has one place that maps the Pricing module's pure enum onto
/// presentation. `CostKind` itself stays UI-free per the Pricing module's own
/// contract — this extension lives in the app target, not the package.
///
/// Colors follow the dataviz house rule "categorical hues assigned in fixed
/// order, never cycled": `.server` keeps the brand accent (servers are the
/// dominant, identity-defining resource), and the remaining six kinds take
/// dark-mode-tuned categorical steps validated against the app's `#0A0A0C`
/// canvas (`node scripts/validate_palette.js` — lightness band, chroma
/// floor, and contrast all PASS; worst adjacent CVD separation sits in the
/// legal 8–12 floor band, which is why every kind is always paired with a
/// visible text label — never color alone — in the legend and item rows).
extension CostKind {
    var displayName: String {
        switch self {
        case .server: "Servers"
        case .volume: "Volumes"
        case .primaryIP: "Primary IPs"
        case .floatingIP: "Floating IPs"
        case .loadBalancer: "Load Balancers"
        case .backup: "Backups"
        case .dedicated: "Dedicated & Manual"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .server: "server.rack"
        case .volume: "internaldrive"
        case .primaryIP: "network"
        case .floatingIP: "arrow.triangle.2.circlepath.circle"
        case .loadBalancer: "arrow.triangle.branch"
        case .backup: "clock.arrow.circlepath"
        case .dedicated: "building.2"
        case .other: "questionmark.circle"
        }
    }

    var tintColor: Color {
        switch self {
        case .server: HetzlyColors.accent
        case .primaryIP: Color(hex: 0x3987E5)
        case .volume: Color(hex: 0x199E70)
        case .floatingIP: Color(hex: 0x9085E9)
        case .loadBalancer: Color(hex: 0xD55181)
        case .backup: Color(hex: 0xC98500)
        case .dedicated: Color(hex: 0xD95926)
        case .other: HetzlyColors.textTertiary
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            ForEach(CostKind.allCases, id: \.self) { kind in
                HStack(spacing: Spacing.unit * 2) {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(kind.tintColor)
                        .frame(width: 24)
                    Text(kind.displayName)
                        .bodySecondary()
                }
            }
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
