import HetznerKit
import SwiftUI

/// A single Storage Box's row on `StorageBoxesView`: status, name/username,
/// type/size chips, location flag+city, and a thin usage bar (`stats.size`
/// against the plan's total `storageBoxType.size`). Kept as a plain
/// presentation view — its parent wraps it in a
/// `NavigationLink(value: StorageBoxRoute(...))`.
struct StorageBoxRow: View {
    let box: StorageBox

    private var usageFraction: Double? {
        StorageBoxSupport.usageFraction(used: box.stats.size, capacity: box.storageBoxType.size)
    }

    var body: some View {
        GlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack(spacing: Spacing.unit * 3) {
                    StatusDot(box.resourceStatus)

                    VStack(alignment: .leading, spacing: Spacing.unit) {
                        Text(box.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(HetzlyColors.textPrimary)
                        Text(box.username ?? "Initializing…")
                            .hetzlyMonoNumbers()
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(HetzlyColors.textSecondary)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: Spacing.unit * 2) {
                    GlassChip(box.storageBoxType.name, systemImage: "externaldrive")
                    GlassChip(StorageBoxSupport.bytes(box.storageBoxType.size))
                    GlassChip("\(flagEmoji(countryCode: box.location.country)) \(box.location.city)")
                }

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    StorageBoxUsageBar(fraction: usageFraction)
                    Text("\(StorageBoxSupport.bytes(box.stats.size)) of \(StorageBoxSupport.bytes(box.storageBoxType.size)) used")
                        .caption()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 3) {
            StorageBoxRow(box: StorageBoxPreviewFixtures.box)
            StorageBoxRow(box: StorageBoxPreviewFixtures.initializingBox)
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
