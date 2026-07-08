import SwiftUI

/// Glass segmented capsule choosing between Server Detail's Control and
/// Analytics panels — same construction as `MetricsRangePicker` (one
/// `glassSurface` capsule, a tinted capsule sliding under the selection via
/// `matchedGeometryEffect`) so the two segmented controls on this screen
/// read as the same control family.
struct ServerDetailTabPicker: View {
    @Binding var selection: ServerDetailTab

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ServerDetailTab.allCases) { tab in
                Button {
                    withAnimation(.snappy) { selection = tab }
                } label: {
                    Text(tab.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == tab ? HetzlyColors.textPrimary : HetzlyColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.unit * 2)
                        .background {
                            if selection == tab {
                                Capsule(style: .continuous)
                                    .fill(HetzlyColors.accent.opacity(0.9))
                                    .matchedGeometryEffect(id: "detail-tab-selection", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(3)
        .glassSurface(Capsule(style: .continuous))
    }
}

#Preview {
    @Previewable @State var selection: ServerDetailTab = .control
    return ZStack {
        CanvasBackground()
        ServerDetailTabPicker(selection: $selection)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
