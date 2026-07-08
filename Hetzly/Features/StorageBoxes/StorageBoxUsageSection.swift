import HetznerKit
import SwiftUI

/// USAGE section on Storage Box Detail: total/data/snapshots usage against
/// the plan's total size, plus a subtle usage bar.
struct StorageBoxUsageSection: View {
    let box: StorageBox

    private var usageFraction: Double? {
        StorageBoxSupport.usageFraction(used: box.stats.size, capacity: box.storageBoxType.size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Usage")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    StorageBoxUsageBar(fraction: usageFraction)

                    DetailInfoRow(
                        label: "Total Used",
                        value: "\(StorageBoxSupport.bytes(box.stats.size)) of \(StorageBoxSupport.bytes(box.storageBoxType.size))"
                    )
                    DetailInfoRow(label: "Data", value: StorageBoxSupport.bytes(box.stats.sizeData))
                    DetailInfoRow(label: "Snapshots", value: StorageBoxSupport.bytes(box.stats.sizeSnapshots))
                }
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        StorageBoxUsageSection(box: StorageBoxPreviewFixtures.box)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
