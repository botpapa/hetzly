import SwiftUI

/// Glass segmented capsule for choosing the metrics chart lookback window
/// (1H · 24H · 7D · 30D). A single `.glassEffect` container with a plain
/// tinted capsule sliding under the selection via `matchedGeometryEffect`,
/// so the control stays within the app's two-glass-layer budget.
struct MetricsRangePicker: View {
    @Binding var selection: MetricsRange

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MetricsRange.allCases) { range in
                Button {
                    withAnimation(.snappy) { selection = range }
                } label: {
                    Text(range.label)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(selection == range ? HetzlyColors.textPrimary : HetzlyColors.textSecondary)
                        .padding(.horizontal, Spacing.unit * 3)
                        .padding(.vertical, Spacing.unit * 1.5)
                        .background {
                            if selection == range {
                                Capsule(style: .continuous)
                                    .fill(HetzlyColors.accent.opacity(0.9))
                                    .matchedGeometryEffect(id: "range-selection", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassSurface(Capsule(style: .continuous))
    }
}

#Preview {
    @Previewable @State var selection: MetricsRange = .oneDay
    return ZStack {
        CanvasBackground()
        MetricsRangePicker(selection: $selection)
    }
    .preferredColorScheme(.dark)
}
