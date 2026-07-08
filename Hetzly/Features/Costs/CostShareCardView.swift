import SwiftUI

/// The exportable cost summary card, rendered off-screen by `ImageRenderer`
/// for the Costs tab's ShareLink. Laid out at 540×675 points and rendered
/// at `scale: 2` → a 1080×1350 pixel image (the 4:5 portrait social/share
/// aspect). Always dark: it's a standalone artifact, so it commits to the
/// app's canvas look regardless of device appearance.
struct CostShareCardView: View {
    let monthToDate: Decimal
    let projected: Decimal
    let currency: String
    let monthTitle: String
    /// (project name, projected monthly total), pre-sorted descending.
    let projectTotals: [(name: String, projected: Decimal)]

    static let size = CGSize(width: 540, height: 675)

    var body: some View {
        ZStack {
            HetzlyColors.canvas
            RadialGradient(
                colors: [Color(hex: 0x111114), HetzlyColors.canvas],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )

            VStack(alignment: .leading, spacing: 28) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    Text("MONTH TO DATE")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(HetzlyColors.textTertiary)

                    Text(monthToDate, format: .currency(code: currency))
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(HetzlyColors.textPrimary)

                    Text("projected \(projected, format: .currency(code: currency)) this month")
                        .font(.system(size: 18, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                projectList

                Spacer(minLength: 0)

                footer
            }
            .padding(44)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Hetzly")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(HetzlyColors.textPrimary)
            Circle()
                .fill(HetzlyColors.accent)
                .frame(width: 8, height: 8)
                .offset(y: -1)
            Spacer()
            Text(monthTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(HetzlyColors.textSecondary)
        }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BY PROJECT")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(HetzlyColors.textTertiary)

            ForEach(Array(projectTotals.prefix(6).enumerated()), id: \.offset) { _, project in
                HStack(alignment: .firstTextBaseline) {
                    Text(project.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(HetzlyColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text("\(project.projected, format: .currency(code: currency))/mo")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }
            }

            if projectTotals.count > 6 {
                Text("+ \(projectTotals.count - 6) more")
                    .font(.system(size: 14))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
        }
    }

    private var footer: some View {
        Text("Computed on-device from live inventory × Hetzner pricing. Excludes traffic overage & one-time fees.")
            .font(.system(size: 12))
            .foregroundStyle(HetzlyColors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Renders `CostShareCardView` into a shareable image. `ImageRenderer` is
/// `@MainActor`; the async wrapper exists so `CostsView` can await it from a
/// `.task` without blocking a button tap, and so a re-render triggered by
/// fresh data simply replaces the previous image.
@MainActor
enum CostShareCardRenderer {
    static func render(
        monthToDate: Decimal,
        projected: Decimal,
        currency: String,
        monthTitle: String,
        projectTotals: [(name: String, projected: Decimal)]
    ) async -> Image? {
        // Yield once so rendering never races the same runloop turn as the
        // state change that scheduled it.
        await Task.yield()

        let card = CostShareCardView(
            monthToDate: monthToDate,
            projected: projected,
            currency: currency,
            monthTitle: monthTitle,
            projectTotals: projectTotals
        )
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2 // 540×675 pt → 1080×1350 px
        renderer.proposedSize = ProposedViewSize(CostShareCardView.size)

        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

#Preview {
    ScrollView([.horizontal, .vertical]) {
        CostShareCardView(
            monthToDate: Decimal(string: "38.62") ?? 0,
            projected: Decimal(string: "154.90") ?? 0,
            currency: "EUR",
            monthTitle: "July 2026",
            projectTotals: [
                (name: "Production", projected: Decimal(string: "84.30") ?? 0),
                (name: "Staging", projected: Decimal(string: "21.60") ?? 0),
                (name: "Playground", projected: Decimal(string: "10.00") ?? 0),
            ]
        )
        .scaleEffect(0.6, anchor: .topLeading)
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
