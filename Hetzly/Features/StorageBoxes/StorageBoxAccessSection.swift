import HetznerKit
import SwiftUI

/// One of the box-level protocols `StorageBoxAccessSection` exposes as a
/// toggle. Mirrors the individual optional parameters on
/// `StorageBoxClient.updateAccessSettings(id:reachableExternally:sambaEnabled:sshEnabled:webdavEnabled:zfsEnabled:)`
/// — each toggle sends only the one flag that changed, leaving the rest
/// untouched server-side.
enum StorageBoxAccessProtocol: String, Identifiable {
    case reachableExternally, samba, ssh, webdav

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reachableExternally: "Reachable Externally"
        case .samba: "Samba / CIFS"
        case .ssh: "SSH / SFTP / SCP"
        case .webdav: "WebDAV"
        }
    }

    var systemImage: String {
        switch self {
        case .reachableExternally: "globe"
        case .samba: "network"
        case .ssh: "terminal"
        case .webdav: "cloud"
        }
    }
}

/// ACCESS section on Storage Box Detail: protocol toggles (Samba/SSH/WebDAV)
/// plus external reachability, each gated by a confirmation dialog before
/// the API call fires. Toggles disable while any change is in flight.
///
/// The underlying `updateAccessSettings` call returns a queued `Action`
/// (not the updated `StorageBox`) — the caller is expected to reload the
/// box afterward, so this view always renders from whatever `settings` it's
/// handed rather than caching its own copy.
struct StorageBoxAccessSection: View {
    let settings: StorageBoxAccessSettings
    var supported: Bool = true
    var isPerformingAction: Bool = false
    var onToggle: (StorageBoxAccessProtocol, Bool) -> Void = { _, _ in }

    @State private var pendingChange: (proto: StorageBoxAccessProtocol, newValue: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Access")
            if supported {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                        toggleRow(.reachableExternally, isOn: settings.reachableExternally)
                        Divider().overlay(Color.white.opacity(0.08))
                        toggleRow(.samba, isOn: settings.sambaEnabled)
                        Divider().overlay(Color.white.opacity(0.08))
                        toggleRow(.ssh, isOn: settings.sshEnabled)
                        Divider().overlay(Color.white.opacity(0.08))
                        toggleRow(.webdav, isOn: settings.webdavEnabled)
                    }
                }
            } else {
                GlassCard {
                    Text("Access settings aren't supported by this version of Hetzly yet.")
                        .caption()
                }
            }
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: confirmBinding,
            titleVisibility: .visible
        ) {
            Button(confirmActionTitle) { commitPendingChange() }
            Button("Cancel", role: .cancel) { pendingChange = nil }
        } message: {
            Text("This changes how this Storage Box can be reached.")
        }
    }

    private func toggleRow(_ proto: StorageBoxAccessProtocol, isOn: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in pendingChange = (proto, newValue) }
        )) {
            Label(proto.title, systemImage: proto.systemImage)
                .foregroundStyle(HetzlyColors.textPrimary)
        }
        .tint(HetzlyColors.accent)
        .disabled(isPerformingAction)
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { pendingChange != nil }, set: { if !$0 { pendingChange = nil } })
    }

    private var confirmTitle: String {
        pendingChange.map { "\($0.newValue ? "Enable" : "Disable") \($0.proto.title)" } ?? ""
    }

    private var confirmActionTitle: String {
        pendingChange?.newValue == true ? "Enable" : "Disable"
    }

    private func commitPendingChange() {
        guard let pendingChange else { return }
        self.pendingChange = nil
        onToggle(pendingChange.proto, pendingChange.newValue)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        StorageBoxAccessSection(settings: StorageBoxPreviewFixtures.accessSettings)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
