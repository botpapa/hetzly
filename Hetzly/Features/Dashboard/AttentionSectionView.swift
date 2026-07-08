import SwiftUI

/// "ATTENTION" section: every server across every project that isn't
/// settled into `.running`/`.off`. Only rendered by the parent when
/// non-empty. The alarm mascot sits beside the header, respecting
/// `AppSettings.mascotEnabled`.
struct AttentionSectionView: View {
    let items: [ServerListItem]
    let cpuSamples: [String: [Double]]
    let mascotEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack {
                SectionLabel("Attention")
                Spacer()
                if mascotEnabled {
                    MascotView(state: .alarm, scale: 2)
                }
            }

            VStack(spacing: Spacing.unit * 2) {
                ForEach(items) { item in
                    NavigationLink(value: ServerRoute(projectID: item.projectID, serverID: item.serverID)) {
                        ServerRowView(item: item, cpuSamples: cpuSamples[item.id])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            ScrollView {
                AttentionSectionView(
                    items: [
                        ServerListItem(
                            projectID: UUID(), serverID: 1, name: "worker-03",
                            status: .stopping, typeName: "cx22", city: "Ashburn", countryCode: "US"
                        ),
                        ServerListItem(
                            projectID: UUID(), serverID: 2, name: "migrating-01",
                            status: .migrating, typeName: "cx32", city: "Falkenstein", countryCode: "DE"
                        ),
                    ],
                    cpuSamples: [:],
                    mascotEnabled: true
                )
                .padding(Spacing.screenMargin)
            }
        }
    }
    .preferredColorScheme(.dark)
}
