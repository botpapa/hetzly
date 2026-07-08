import SwiftUI

/// Client-side filter sheet for the Server Market list: price ceiling, min
/// CPU benchmark, min RAM, min HDD — every row toggles on/off independently
/// so "no filter" stays the obvious default.
struct MarketFilterSheet: View {
    @Binding var filter: MarketFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 5) {
            HStack {
                Text("Filter Market")
                    .bodyPrimary()
                    .fontWeight(.semibold)
                Spacer()
                Button("Reset") { withAnimation(.snappy) { filter = MarketFilter() } }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.textSecondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 5) {
                    OptionalSliderRow(
                        title: "Max Price",
                        value: decimalBinding(\.priceCeiling),
                        range: 10...500,
                        step: 10,
                        format: { "€\(Int($0))/mo" }
                    )
                    OptionalSliderRow(
                        title: "Min CPU Benchmark",
                        value: intBinding(\.minCPUBenchmark),
                        range: 500...20000,
                        step: 500,
                        format: { "\(Int($0))" }
                    )
                    OptionalSliderRow(
                        title: "Min RAM",
                        value: intBinding(\.minRAMGB),
                        range: 4...256,
                        step: 4,
                        format: { "\(Int($0)) GB" }
                    )
                    OptionalSliderRow(
                        title: "Min HDD",
                        value: doubleBinding(\.minHDDTB),
                        range: 0.5...20,
                        step: 0.5,
                        format: { String(format: "%.1f TB", $0) }
                    )
                }
            }

            PrimaryCTA(title: "Show Results") { dismiss() }
                .frame(maxWidth: .infinity)
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    private func decimalBinding(_ keyPath: WritableKeyPath<MarketFilter, Decimal?>) -> Binding<Double?> {
        Binding<Double?>(
            get: { filter[keyPath: keyPath].map { NSDecimalNumber(decimal: $0).doubleValue } },
            set: { filter[keyPath: keyPath] = $0.map { Decimal($0) } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<MarketFilter, Int?>) -> Binding<Double?> {
        Binding<Double?>(
            get: { filter[keyPath: keyPath].map(Double.init) },
            set: { filter[keyPath: keyPath] = $0.map { Int($0) } }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<MarketFilter, Double?>) -> Binding<Double?> {
        Binding<Double?>(
            get: { filter[keyPath: keyPath] },
            set: { filter[keyPath: keyPath] = $0 }
        )
    }
}

/// A toggle + slider pair for one optional numeric filter: off means "no
/// constraint", on reveals a slider seeded at the range's midpoint.
private struct OptionalSliderRow: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    private var isOn: Bool { value != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            Toggle(isOn: toggleBinding) {
                HStack {
                    Text(title).bodyPrimary()
                    Spacer()
                    if let value {
                        Text(format(value)).hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textSecondary)
                    }
                }
            }
            .tint(HetzlyColors.accent)

            if let value {
                Slider(
                    value: Binding(get: { value }, set: { self.value = $0 }),
                    in: range,
                    step: step
                )
                .tint(HetzlyColors.accent)
            }
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                withAnimation(.snappy) {
                    value = newValue ? range.lowerBound + (range.upperBound - range.lowerBound) / 2 : nil
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var filter = MarketFilter(priceCeiling: 120, minRAMGB: 32)

    return ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        MarketFilterSheet(filter: $filter)
    }
}
