import HetznerKit
import SwiftUI
import UIKit

/// The hero glass card at the top of Storage Box Detail: status, name (tap
/// to rename, when supported), copyable username and server hostname,
/// location, and created date.
struct StorageBoxHeroCard: View {
    let box: StorageBox
    var renameSupported: Bool = true
    var onTapName: () -> Void = {}

    @State private var didCopyUsername = false
    @State private var didCopyServer = false
    @State private var copyHaptic = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                HStack(spacing: Spacing.unit * 2) {
                    StatusDot(box.resourceStatus)
                    Text(box.statusDisplayName)
                        .bodySecondary()
                    Spacer()
                }

                Button(action: onTapName) {
                    HStack(spacing: Spacing.unit * 2) {
                        Text(box.name)
                            .font(.system(size: 22, weight: .bold))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .foregroundStyle(HetzlyColors.textPrimary)
                        if renameSupported {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HetzlyColors.textTertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!renameSupported)
                .accessibilityLabel(renameSupported ? "\(box.name), rename" : box.name)
                .accessibilityHint(renameSupported ? "Double tap to rename this Storage Box" : "")

                identifierBlock

                chipRow

                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    DetailInfoRow(
                        label: "Location",
                        value: "\(flagEmoji(countryCode: box.location.country)) \(box.location.city)"
                    )
                    DetailInfoRow(label: "Created", value: StorageBoxSupport.dateString(box.created))
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: copyHaptic)
    }

    @ViewBuilder
    private var identifierBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.unit) {
            if let username = box.username {
                copyRow(label: "Username", value: username, didCopy: didCopyUsername) {
                    copy(username, isUsername: true)
                }
            }
            if let server = box.server {
                copyRow(label: "Server", value: server, didCopy: didCopyServer) {
                    copy(server, isUsername: false)
                }
            }
            if box.username == nil && box.server == nil {
                Text("Still initializing — credentials appear once provisioning finishes.")
                    .caption()
            }
        }
    }

    private func copyRow(label: String, value: String, didCopy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.unit * 2) {
                Text(value)
                    .hetzlyMonoNumbers()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(HetzlyColors.textSecondary)
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HetzlyColors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(value)")
        .accessibilityHint(didCopy ? "Copied" : "Double tap to copy")
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.unit * 2) {
                GlassChip(box.storageBoxType.name, systemImage: "externaldrive")
                GlassChip(box.system ?? "—", systemImage: "server.rack")
            }
        }
    }

    private func copy(_ value: String, isUsername: Bool) {
        UIPasteboard.general.string = value
        copyHaptic.toggle()
        withAnimation(.snappy) {
            if isUsername { didCopyUsername = true } else { didCopyServer = true }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) {
                if isUsername { didCopyUsername = false } else { didCopyServer = false }
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        StorageBoxHeroCard(box: StorageBoxPreviewFixtures.box, onTapName: {})
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
