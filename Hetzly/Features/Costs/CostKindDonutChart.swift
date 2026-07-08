import Charts
import HetznerKit
import SwiftUI

/// Donut of combined projected spend by resource kind (Swift Charts
/// `SectorMark`), with glass legend chips underneath. Colors come from
/// `CostKind.tintColor` (fixed categorical assignment — see `CostKind+UI`);
/// because the palette's worst color-blind pair sits in the floor band,
/// every slice is always paired with a labeled legend chip and never relies
/// on hue alone.
struct CostKindDonutChart: View {
    let shares: [CostsViewModel.KindShare]
    let currency: String

    private var total: Decimal {
        shares.reduce(0) { $0 + $1.projected }
    }

    var body: some View {
        VStack(spacing: Spacing.unit * 4) {
            chart
                .frame(height: 190)

            legend
        }
    }

    private var chart: some View {
        Chart(shares) { share in
            SectorMark(
                angle: .value("Projected", CostsSupport.double(share.projected)),
                innerRadius: .ratio(0.66),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(share.kind.tintColor)
            .accessibilityLabel(share.kind.displayName)
            .accessibilityValue(Text(share.projected, format: .currency(code: currency)))
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    VStack(spacing: 2) {
                        Text(total, format: .currency(code: currency))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(HetzlyColors.textPrimary)
                        Text("projected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HetzlyColors.textTertiary)
                    }
                    .frame(maxWidth: frame.width * 0.55)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }

    /// Wrapping rows of glass chips: color dot + kind name + amount.
    private var legend: some View {
        FlowingChips(spacing: Spacing.unit * 2) {
            ForEach(shares) { share in
                CostKindLegendChip(share: share, currency: currency)
            }
        }
    }
}

/// One legend entry: a small color dot, the kind's name, and its projected
/// monthly amount, on a glass capsule.
struct CostKindLegendChip: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let share: CostsViewModel.KindShare
    let currency: String

    private var capsule: Capsule { Capsule(style: .continuous) }

    var body: some View {
        HStack(spacing: Spacing.unit * 1.5) {
            Circle()
                .fill(share.kind.tintColor)
                .frame(width: 7, height: 7)
            Text(share.kind.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HetzlyColors.textSecondary)
            Text(share.projected, format: .currency(code: currency))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(HetzlyColors.textPrimary)
        }
        .padding(.horizontal, Spacing.unit * 2.5)
        .padding(.vertical, Spacing.unit * 1.5)
        .background {
            if reduceTransparency {
                capsule
                    .fill(Color(white: 0.12))
                    .overlay { capsule.strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
            } else {
                Color.clear
            }
        }
        .modifier(LegendChipGlass(shape: capsule, isEnabled: !reduceTransparency))
        .accessibilityElement(children: .combine)
    }
}

private struct LegendChipGlass: ViewModifier {
    let shape: Capsule
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.glassEffect(.regular, in: shape)
        } else {
            content
        }
    }
}

/// Minimal wrapping layout for the legend chips: lays children left to
/// right, flowing onto new rows when the line fills, centered per row.
struct FlowingChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let widthIfAdded = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && widthIfAdded > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.indices.append(index)
            current.width = current.indices.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            CostKindDonutChart(
                shares: [
                    CostsViewModel.KindShare(kind: .server, projected: Decimal(string: "84.30") ?? 0),
                    CostsViewModel.KindShare(kind: .dedicated, projected: Decimal(string: "39.00") ?? 0),
                    CostsViewModel.KindShare(kind: .volume, projected: Decimal(string: "14.40") ?? 0),
                    CostsViewModel.KindShare(kind: .loadBalancer, projected: Decimal(string: "5.39") ?? 0),
                    CostsViewModel.KindShare(kind: .primaryIP, projected: Decimal(string: "3.58") ?? 0),
                    CostsViewModel.KindShare(kind: .backup, projected: Decimal(string: "2.02") ?? 0),
                ],
                currency: "EUR"
            )
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
